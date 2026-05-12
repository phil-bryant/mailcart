SHELL := /bin/zsh

APP_NAME ?= OutlookMailApp
UI_BUILD_DIR ?= .build/ui
PROJECT_FILE ?= macos_app/$(APP_NAME).xcodeproj
SCHEME ?= $(APP_NAME)
CONFIGURATION ?= Debug
DERIVED_DATA ?= $(UI_BUILD_DIR)/DerivedData
SAST_REPORT_DIR ?= reports/sast
APP_BUNDLE := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
APP_EXECUTABLE := $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
OUTLOOK_GRAPH_TOKEN_PSA_ITEM ?= outlook_graph_token
OUTLOOK_GRAPH_TOKEN_PSA_FIELD ?= password

.DEFAULT_GOAL := build

.PHONY: help build test ui-test run run-matchy-api crash-reporter-smoke sast sast-report clean \
	_cpp-test _bridge-check _ui-typecheck _ui-build _ui-rebuild _non-ui-tests _ui-smoke \
	_sast_shell _sast_semgrep _sast_clang_tidy _sast_clang_tidy_report _sast_secrets

#R001: Expose discoverable developer entrypoints through a help target.
help:
	@echo "Targets:"
	@echo "  make build   - Build bridge checks, UI typecheck, and app binary"
	@echo "  make test    - Run C++ integration test and non-UI ./tests/* tests"
	@echo "  make ui-test - Run UI BATS tests and app smoke launch check"
	@echo "  make run     - Build and launch macOS app"
	@echo "  make run-matchy-api - Run lightweight API for Matchy search/move calls"
	@echo "  make crash-reporter-smoke - Verify PLCrashReporter crash capture and replay flow"
	@echo "  make sast    - Run blocking SAST checks (ShellCheck, Semgrep, clang-tidy, gitleaks)"
	@echo "  make sast-report - Run non-blocking extended clang-tidy report checks"
	@echo "  make clean   - Remove local build artifacts"

#R005: Build all repository deliverables and checks.
#R010: Build lane includes Objective-C and Objective-C++ bridge compilation checks.
#R015: Build lane includes SwiftUI typecheck with bridging configuration.
#R020: Build lane reuses existing app binary when available.
#R025: Build lane rebuilds app deterministically when binary is missing.
build: _bridge-check _ui-typecheck _ui-build

#R005: Run non-UI test lanes, including C++ integration coverage.
test: _cpp-test _non-ui-tests

#R035: Run UI-focused test lane.
ui-test: _ui-build
	@bats "tests/sh/UI.bats"
	@$(MAKE) _ui-smoke
	@if [ "$${RUN_CRASH_REPORTER_SMOKE_TEST:-false}" = "true" ]; then \
		echo "▶ Running PLCrashReporter smoke verification..."; \
		$(MAKE) crash-reporter-smoke; \
	else \
		echo "ℹ️  Skipping PLCrashReporter smoke verification (RUN_CRASH_REPORTER_SMOKE_TEST=false)."; \
	fi

#R045: Expose a consolidated SAST lane for all repository content.
sast: _sast_shell _sast_semgrep _sast_clang_tidy _sast_secrets
	@echo "SAST checks completed."

#R070: Expose a non-blocking extended SAST reporting lane.
sast-report: _sast_clang_tidy_report
	@echo "SAST report checks completed."

#R030: Launch the built app bundle through a dedicated run target.
run: build
	@if ! command -v 1psa >/dev/null 2>&1; then \
		echo "1psa is required for make run. Install it with ./01_install_prerequisites.sh"; \
		exit 1; \
	fi; \
	OUTLOOK_GRAPH_TOKEN="$$(1psa -f "$(OUTLOOK_GRAPH_TOKEN_PSA_ITEM)" "$(OUTLOOK_GRAPH_TOKEN_PSA_FIELD)" 2>/dev/null || true)"; \
	if [ -z "$$OUTLOOK_GRAPH_TOKEN" ]; then \
		echo "Unable to read outlook_graph_token from 1psa item '$(OUTLOOK_GRAPH_TOKEN_PSA_ITEM)' field '$(OUTLOOK_GRAPH_TOKEN_PSA_FIELD)'."; \
		echo "See README.md for token setup steps."; \
		exit 1; \
	fi; \
	OUTLOOK_GRAPH_TOKEN="$$OUTLOOK_GRAPH_TOKEN" "$(APP_EXECUTABLE)" >/tmp/outlook-ui.log 2>&1 & \
	APP_PID=$$!; \
	echo "Launched $(APP_NAME) with Graph token (pid $$APP_PID)."

run-matchy-api:
	@python3 "18_run_matchy_mailcart_api.py"

#R080: Expose dedicated crash-reporter smoke verification lane.
crash-reporter-smoke: _ui-build
	@./17_verify_macos_crash_reporter.sh

_cpp-test:
	@mkdir -p ".build"
	@clang++ -std=c++17 \
		-I"cpp_core/include" \
		"cpp_core/src/mailcart.cpp" "cpp_core/src/mime_content.cpp" "cpp_core/src/outlook_mailcart.cpp" "cpp_core/src/outlook_client.cpp" "cpp_core/tests/outlook_integration_test.cpp" \
		-o ".build/outlook_integration_test"
	@".build/outlook_integration_test"

_non-ui-tests:
	@typeset -a NON_UI_TESTS; \
	NON_UI_TESTS=(); \
	for TEST_FILE in tests/sh/*.bats; do \
		if [ -f "$$TEST_FILE" ]; then \
			if [ "$$(basename "$$TEST_FILE")" != "UI.bats" ]; then \
				NON_UI_TESTS+=("$$TEST_FILE"); \
			fi; \
		fi; \
	done; \
	if [ "$${#NON_UI_TESTS[@]}" -gt 0 ]; then \
		bats "$${NON_UI_TESTS[@]}"; \
	else \
		echo "No non-UI shell tests found."; \
	fi

#R010: Compile bridge translation units into local object files.
_bridge-check:
	@mkdir -p ".build"
	@xcrun --sdk macosx clang++ -std=c++17 -fobjc-arc -x objective-c++ \
		-c "macos_app/Bridge/OutlookClientBridge.mm" \
		-I"cpp_core/include" -I"macos_app/Bridge" -o ".build/OutlookClientBridge.o"
	@xcrun --sdk macosx clang -fobjc-arc -x objective-c \
		-c "macos_app/Bridge/OutlookBridgeModels.m" \
		-I"macos_app/Bridge" -o ".build/OutlookBridgeModels.o"
	@echo "Bridge files compiled successfully."

#R015: Typecheck Swift UI sources with the Objective-C bridging header.
_ui-typecheck:
	@xcrun swiftc -typecheck \
		"macos_app/UI/OutlookMailApp.swift" \
		"macos_app/UI/CrashReporterService.swift" \
		"macos_app/UI/OutlookMailContentView.swift" \
		"macos_app/UI/OutlookMailViewModel.swift" \
		-sdk "$$(xcrun --sdk macosx --show-sdk-path)" \
		-target arm64-apple-macos13.0 \
		-import-objc-header "macos_app/OutlookMail-Bridging-Header.h" \
		-Xcc -I"macos_app/Bridge"
	@echo "SwiftUI sources typecheck successfully."

#R020: Reuse an existing built app binary when available.
_ui-build:
	@REBUILD_REASON=""; \
	if [ ! -x "$(APP_EXECUTABLE)" ]; then \
		REBUILD_REASON="missing"; \
	fi; \
	if [ -x "$(APP_EXECUTABLE)" ]; then \
		for SOURCE_FILE in \
			macos_app/UI/OutlookMailApp.swift \
			macos_app/UI/CrashReporterService.swift \
			macos_app/UI/OutlookMailContentView.swift \
			macos_app/UI/OutlookMailViewModel.swift \
			macos_app/Bridge/OutlookClientBridge.h \
			macos_app/Bridge/OutlookClientBridge.mm \
			macos_app/Bridge/OutlookBridgeModels.h \
			macos_app/Bridge/OutlookBridgeModels.m \
			macos_app/OutlookMail-Bridging-Header.h \
			macos_app/project.yml \
			macos_app/Info.plist \
			cpp_core/include/mailcart.hpp \
			cpp_core/include/mime_content.hpp \
			cpp_core/include/outlook_mailcart.hpp \
			cpp_core/include/outlook_client.hpp \
			cpp_core/src/mailcart.cpp \
			cpp_core/src/mime_content.cpp \
			cpp_core/src/outlook_mailcart.cpp \
			cpp_core/src/outlook_client.cpp; do \
			if [ "$$SOURCE_FILE" -nt "$(APP_EXECUTABLE)" ]; then \
				REBUILD_REASON="stale"; \
			fi; \
		done; \
	fi; \
	if [ "$$REBUILD_REASON" = "missing" ] || [ "$$REBUILD_REASON" = "stale" ]; then \
		$(MAKE) _ui-rebuild; \
	else \
		echo "Using existing build at $(APP_BUNDLE)"; \
	fi

#R025: Perform deterministic full rebuild from Xcode project spec.
_ui-rebuild:
	@mkdir -p "$(UI_BUILD_DIR)"
	@xcodegen generate --spec "macos_app/project.yml"
	@rm -rf "$(DERIVED_DATA)"
	@xcodebuild \
		-project "$(PROJECT_FILE)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		CODE_SIGNING_ALLOWED=NO \
		clean build
	@echo "Built $(APP_BUNDLE)"

_ui-smoke:
	@"$(APP_EXECUTABLE)" >/tmp/outlook-ui.log 2>&1 & \
	APP_PID=$$!; \
	sleep 2; \
	if ps -p $$APP_PID >/dev/null; then \
		kill $$APP_PID; \
		wait $$APP_PID >/dev/null 2>&1 || true; \
		echo "UI launched successfully (smoke test passed)."; \
	else \
		echo "UI process exited before smoke timeout."; \
		exit 1; \
	fi

#R050: Run shell-script static analysis through ShellCheck.
_sast_shell:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck is required for make sast. Install it with ./01_install_prerequisites.sh"; \
		exit 1; \
	fi
	@typeset -a SHELL_FILES; \
	SHELL_FILES=(**/*.sh(N)); \
	if [ "$${#SHELL_FILES[@]}" -gt 0 ]; then \
		shellcheck "$${SHELL_FILES[@]}"; \
	else \
		echo "No shell scripts discovered for ShellCheck scan."; \
	fi

#R055: Run Semgrep with repository-scoped rules.
_sast_semgrep:
	@if ! command -v semgrep >/dev/null 2>&1; then \
		echo "semgrep is required for make sast. Install semgrep to continue."; \
		exit 1; \
	fi
	@semgrep --config auto --config ".semgrep.yml" --error --quiet .

#R060: Run clang-tidy on C++ and bridge Objective-C(++) sources.
_sast_clang_tidy:
	@CLANG_TIDY_BIN="$$(command -v clang-tidy 2>/dev/null || true)"; \
	if [ -z "$$CLANG_TIDY_BIN" ]; then \
		LLVM_PREFIX="$$(brew --prefix llvm 2>/dev/null || true)"; \
		if [ -n "$$LLVM_PREFIX" ] && [ -x "$$LLVM_PREFIX/bin/clang-tidy" ]; then \
			CLANG_TIDY_BIN="$$LLVM_PREFIX/bin/clang-tidy"; \
		fi; \
	fi; \
	if [ -z "$$CLANG_TIDY_BIN" ]; then \
		echo "clang-tidy is required for make sast. Install prerequisites with ./01_install_prerequisites.sh"; \
		exit 1; \
	fi; \
	mkdir -p "$(SAST_REPORT_DIR)"; \
	CLANG_TIDY_LOG="$(SAST_REPORT_DIR)/clang-tidy-blocking.log"; \
	: > "$$CLANG_TIDY_LOG"; \
	CLANG_TIDY_COMMON_FLAGS="--config-file=.clang-tidy"; \
	"$$CLANG_TIDY_BIN" \
		$$CLANG_TIDY_COMMON_FLAGS \
		"cpp_core/src/mailcart.cpp" \
		"cpp_core/src/mime_content.cpp" \
		"cpp_core/src/outlook_mailcart.cpp" \
		"cpp_core/src/outlook_client.cpp" \
		-- -std=c++17 -I"cpp_core/include" 2>&1 | tee -a "$$CLANG_TIDY_LOG"; \
	xcrun --sdk macosx "$$CLANG_TIDY_BIN" \
		$$CLANG_TIDY_COMMON_FLAGS \
		"macos_app/Bridge/OutlookClientBridge.mm" \
		-- -std=c++17 -fobjc-arc -x objective-c++ -I"cpp_core/include" -I"macos_app/Bridge" 2>&1 | tee -a "$$CLANG_TIDY_LOG"; \
	xcrun --sdk macosx "$$CLANG_TIDY_BIN" \
		$$CLANG_TIDY_COMMON_FLAGS \
		"macos_app/Bridge/OutlookBridgeModels.m" \
		-- -fobjc-arc -x objective-c -I"macos_app/Bridge" 2>&1 | tee -a "$$CLANG_TIDY_LOG"; \
	if python3 -c 'import pathlib,re,sys; text=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace"); pattern=re.compile(r"error: .*\[[^\]]*-warnings-as-errors[^\]]*\]"); raise SystemExit(0 if pattern.search(text) else 1)' "$$CLANG_TIDY_LOG"; then \
		echo "clang-tidy blocking findings detected. See $$CLANG_TIDY_LOG."; \
		exit 1; \
	fi

#R075: Run non-blocking extended clang-tidy report checks.
_sast_clang_tidy_report:
	@CLANG_TIDY_BIN="$$(command -v clang-tidy 2>/dev/null || true)"; \
	if [ -z "$$CLANG_TIDY_BIN" ]; then \
		LLVM_PREFIX="$$(brew --prefix llvm 2>/dev/null || true)"; \
		if [ -n "$$LLVM_PREFIX" ] && [ -x "$$LLVM_PREFIX/bin/clang-tidy" ]; then \
			CLANG_TIDY_BIN="$$LLVM_PREFIX/bin/clang-tidy"; \
		fi; \
	fi; \
	if [ -z "$$CLANG_TIDY_BIN" ]; then \
		echo "clang-tidy is required for make sast-report. Install prerequisites with ./01_install_prerequisites.sh"; \
		exit 1; \
	fi; \
	mkdir -p "$(SAST_REPORT_DIR)"; \
	CLANG_TIDY_LOG="$(SAST_REPORT_DIR)/clang-tidy-report.log"; \
	: > "$$CLANG_TIDY_LOG"; \
	CLANG_TIDY_COMMON_FLAGS="--config-file=.clang-tidy.report"; \
	"$$CLANG_TIDY_BIN" \
		$$CLANG_TIDY_COMMON_FLAGS \
		"cpp_core/src/mailcart.cpp" \
		"cpp_core/src/mime_content.cpp" \
		"cpp_core/src/outlook_mailcart.cpp" \
		"cpp_core/src/outlook_client.cpp" \
		-- -std=c++17 -I"cpp_core/include" 2>&1 | tee -a "$$CLANG_TIDY_LOG" || true; \
	xcrun --sdk macosx "$$CLANG_TIDY_BIN" \
		$$CLANG_TIDY_COMMON_FLAGS \
		"macos_app/Bridge/OutlookClientBridge.mm" \
		-- -std=c++17 -fobjc-arc -x objective-c++ -I"cpp_core/include" -I"macos_app/Bridge" 2>&1 | tee -a "$$CLANG_TIDY_LOG" || true; \
	xcrun --sdk macosx "$$CLANG_TIDY_BIN" \
		$$CLANG_TIDY_COMMON_FLAGS \
		"macos_app/Bridge/OutlookBridgeModels.m" \
		-- -fobjc-arc -x objective-c -I"macos_app/Bridge" 2>&1 | tee -a "$$CLANG_TIDY_LOG" || true

#R065: Run repository secret scanning through gitleaks.
_sast_secrets:
	@if ! command -v gitleaks >/dev/null 2>&1; then \
		echo "gitleaks is required for make sast. Install gitleaks to continue."; \
		exit 1; \
	fi
	@gitleaks detect --source . --config ".gitleaks.toml" --no-banner --redact --exit-code 1

#R040: Remove generated local artifacts through clean target.
clean:
	@rm -rf ".build" "$(SAST_REPORT_DIR)" "$(PROJECT_FILE)"
	@echo "Cleaned .build artifacts."
