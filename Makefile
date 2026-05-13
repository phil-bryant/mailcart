SHELL := /bin/zsh

APP_NAME ?= Mailcart
UI_BUILD_DIR ?= .build/ui
PROJECT_FILE ?= macos_app/$(APP_NAME).xcodeproj
SCHEME ?= $(APP_NAME)
CONFIGURATION ?= Debug
DERIVED_DATA ?= $(UI_BUILD_DIR)/DerivedData
XCUITEST_PROJECT ?= $(PROJECT_FILE)
XCUITEST_SCHEME ?= MailcartUITests
XCUITEST_DESTINATION ?= platform=macOS
XCUITEST_DERIVED_DATA_PATH ?= $(UI_BUILD_DIR)/DerivedDataUITests
SAST_REPORT_DIR ?= reports/sast
APP_BUNDLE := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
APP_EXECUTABLE := $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
OUTLOOK_GRAPH_TOKEN_PSA_ITEM ?= outlook_graph_token
OUTLOOK_GRAPH_TOKEN_PSA_FIELD ?= password

.DEFAULT_GOAL := help

.PHONY: help build test ui-test run run-ui crash crash-reporter-smoke \
	sast lint clam clean \
	_cpp-test _bridge-check _ui-typecheck _ui-build _ui-rebuild _shell-tests _ui-regression _ui-xcuitests _ui-smoke \
	_sast_shell _sast_semgrep _sast_bandit _sast_detect_secrets _sast_clang_tidy _sast_secrets \
	_lint_swiftlint _lint_python_equivalent \
	verify-macos-crash-reporter run-api

#R001: Expose discoverable developer entrypoints through a help target.
help:
	@echo "Targets:"
	@echo "  make lint    - Run blocking clang-tidy, SwiftLint, and Ruff checks"
	@echo "  make clam    - Run Clam AntiVirus recursive scan for this repository"
	@echo "  make build   - Build bridge checks, UI typecheck, and app binary"
	@echo "  make sast    - Run SAST (ShellCheck, Semgrep, Bandit, detect-secrets, gitleaks)"
	@echo "  make test    - Run C++ integration test and all ./tests/sh/*.bats tests"
	@echo "  make ui-test - Run inline + XCUITest UI regressions and app smoke launch check"
	@echo "  make crash   - Verify PLCrashReporter crash capture and replay flow"
	@echo "  make run-ui  - Build and launch macOS app"
	@echo "  make run-api - Run Matchy-compatible API"
	@echo "  make clean   - Remove local build artifacts"

#R005: Build all repository deliverables and checks.
#R010: Build lane includes Objective-C and Objective-C++ bridge compilation checks.
#R015: Build lane includes SwiftUI typecheck with bridging configuration.
#R020: Build lane reuses existing app binary when available.
#R025: Build lane rebuilds app deterministically when binary is missing.
build: _bridge-check _ui-typecheck _ui-build

#R005: Run C++ integration plus full shell BATS regression coverage.
test: _cpp-test _shell-tests

#R035: Run UI-focused test lane.
ui-test: _ui-build
	@echo "▶ Running inline UI regression checks..."
	@$(MAKE) _ui-regression
	@if [ "$${RUN_XCUITESTS:-true}" = "true" ]; then \
		echo "▶ Running macOS XCUITest regression suite..."; \
		XCUITEST_PROJECT="$(XCUITEST_PROJECT)" XCUITEST_SCHEME="$(XCUITEST_SCHEME)" XCUITEST_DESTINATION="$(XCUITEST_DESTINATION)" XCUITEST_DERIVED_DATA_PATH="$(XCUITEST_DERIVED_DATA_PATH)" XCUITEST_SELECTOR="$${XCUITEST_SELECTOR:-}" $(MAKE) _ui-xcuitests; \
	else \
		echo "ℹ️  Skipping XCUITest regression suite (RUN_XCUITESTS=false)."; \
	fi
	@if [ "$${RUN_UI_SMOKE_TEST:-true}" = "true" ]; then \
		echo "▶ Running UI smoke launch check..."; \
		APP_EXECUTABLE="$(APP_EXECUTABLE)" APP_BUNDLE="$(APP_BUNDLE)" UI_BUILD_DIR="$(UI_BUILD_DIR)" DERIVED_DATA="$(DERIVED_DATA)" PROJECT_FILE="$(PROJECT_FILE)" SCHEME="$(SCHEME)" CONFIGURATION="$(CONFIGURATION)" $(MAKE) _ui-smoke; \
	else \
		echo "ℹ️  Skipping UI smoke launch check (RUN_UI_SMOKE_TEST=false)."; \
	fi
	@if [ "$${RUN_CRASH_REPORTER_SMOKE_TEST:-false}" = "true" ]; then \
		echo "▶ Running PLCrashReporter smoke verification..."; \
		APP_EXECUTABLE="$(APP_EXECUTABLE)" APP_BUNDLE="$(APP_BUNDLE)" UI_BUILD_DIR="$(UI_BUILD_DIR)" DERIVED_DATA="$(DERIVED_DATA)" PROJECT_FILE="$(PROJECT_FILE)" SCHEME="$(SCHEME)" CONFIGURATION="$(CONFIGURATION)" $(MAKE) crash-reporter-smoke; \
	fi

#R045: Expose a consolidated SAST lane for repository security tools.
#R085: Print per-tool headers before each blocking SAST tool lane.
#R090: Print per-tool running notifications before each blocking SAST tool lane.
sast:
	@set +e; \
	HAS_FAILURE=0; \
	echo "+==============================================================================+"; \
	echo "| Security Tool: ShellCheck                                                   |"; \
	echo "| Static linting for shell scripts with security and reliability checks.      |"; \
	echo "| Flags risky shell patterns, quoting bugs, and execution pitfalls.           |"; \
	echo "| URL: https://www.shellcheck.net/                                            |"; \
	echo "+==============================================================================+"; \
	echo "▶ Running ShellCheck..."; \
	$(MAKE) _sast_shell; \
	if [ "$$?" -ne 0 ]; then HAS_FAILURE=1; fi; \
	echo "+==============================================================================+"; \
	echo "| Security Tool: Semgrep                                                      |"; \
	echo "| Static pattern-based scanning for security and correctness issues.          |"; \
	echo "| Uses curated security rules against the repository source tree.             |"; \
	echo "| URL: https://semgrep.dev/docs/                                              |"; \
	echo "+==============================================================================+"; \
	echo "▶ Running Semgrep..."; \
	$(MAKE) _sast_semgrep; \
	if [ "$$?" -ne 0 ]; then HAS_FAILURE=1; fi; \
	echo "+==============================================================================+"; \
	echo "| Security Tool: Bandit                                                       |"; \
	echo "| Python-focused security scanner for common code vulnerabilities.            |"; \
	echo "| Flags insecure usage patterns and risky Python APIs.                        |"; \
	echo "| URL: https://bandit.readthedocs.io/                                         |"; \
	echo "+==============================================================================+"; \
	echo "▶ Running Bandit..."; \
	$(MAKE) _sast_bandit; \
	if [ "$$?" -ne 0 ]; then HAS_FAILURE=1; fi; \
	echo "+==============================================================================+"; \
	echo "| Security Tool: detect-secrets                                               |"; \
	echo "| Scans repository files for potential hard-coded secrets.                    |"; \
	echo "| Detects high-entropy strings and known secret formats.                      |"; \
	echo "| URL: https://github.com/Yelp/detect-secrets                                 |"; \
	echo "+==============================================================================+"; \
	echo "▶ Running detect-secrets..."; \
	$(MAKE) _sast_detect_secrets; \
	if [ "$$?" -ne 0 ]; then HAS_FAILURE=1; fi; \
	echo "+==============================================================================+"; \
	echo "| Security Tool: Gitleaks                                                     |"; \
	echo "| Scans repository content for hard-coded secrets and credentials.            |"; \
	echo "| Detects leaked tokens, keys, and other sensitive data patterns.             |"; \
	echo "| URL: https://github.com/gitleaks/gitleaks                                   |"; \
	echo "+==============================================================================+"; \
	echo "▶ Running gitleaks..."; \
	$(MAKE) _sast_secrets; \
	if [ "$$?" -ne 0 ]; then HAS_FAILURE=1; fi; \
	if [ "$$HAS_FAILURE" -eq 0 ]; then \
		echo "✅ SAST checks completed with no findings."; \
	else \
		echo "❌ SAST checks completed with findings or failures."; \
		exit 1; \
	fi

#R060: Run clang-tidy exclusively through make lint and fail on any findings.
#R070: Expose blocking lint lane status through make lint.
lint:
	@set +e; \
	HAS_FAILURE=0; \
	$(MAKE) _sast_clang_tidy; \
	if [ "$$?" -ne 0 ]; then HAS_FAILURE=1; fi; \
	$(MAKE) _lint_swiftlint; \
	if [ "$$?" -ne 0 ]; then HAS_FAILURE=1; fi; \
	$(MAKE) _lint_python_equivalent; \
	if [ "$$?" -ne 0 ]; then HAS_FAILURE=1; fi; \
	if [ "$$HAS_FAILURE" -eq 0 ]; then \
		echo "✅ lint checks completed with no findings."; \
	else \
		echo "❌ lint checks completed with findings or failures."; \
		exit 1; \
	fi

#R130: Expose ClamAV repository scan through dedicated make target.
#R140: Emit explicit pass/fail summary markers from infected-file count.
clam:
	@if ! command -v clamscan >/dev/null 2>&1; then \
		echo "clamscan is required for make clam. Install ClamAV to continue."; \
		exit 1; \
	fi
	@set +e; \
	mkdir -p "$(SAST_REPORT_DIR)"; \
	CLAM_LOG="$(SAST_REPORT_DIR)/clam-scan.log"; \
	: > "$$CLAM_LOG"; \
	clamscan -r . --log="$$CLAM_LOG"; \
	CLAM_EXIT_CODE="$$?"; \
	INFECTED_FILES="$$(awk -F':' '/Infected files:/ {gsub(/[[:space:]]/, "", $$2); print $$2; exit}' "$$CLAM_LOG")"; \
	if [ -z "$$INFECTED_FILES" ]; then \
		echo "❌ clam scan completed with findings or failures."; \
		echo "Unable to determine infected file count from clamscan output."; \
		exit 1; \
	fi; \
	if [ "$$INFECTED_FILES" -gt 0 ]; then \
		echo "❌ clam scan completed with findings or failures."; \
		exit 1; \
	fi; \
	if [ "$$CLAM_EXIT_CODE" -ne 0 ]; then \
		echo "❌ clam scan completed with findings or failures."; \
		exit 1; \
	fi; \
	echo "✅ clam scan completed with no findings."

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

#R095: Run Matchy-compatible API from scripts path through make entrypoint.
run-api:
	@python3 "scripts/matchy_mailcart_api.py"

#R100: Expose stable entrypoints for crash and Matchy script lanes.
verify-macos-crash-reporter: crash-reporter-smoke

crash: crash-reporter-smoke

run-ui: run

#R080: Expose dedicated crash-reporter smoke verification lane.
crash-reporter-smoke: _ui-build
	@bash "./scripts/verify_macos_crash_reporter.sh"

_cpp-test:
	@mkdir -p ".build"
	@clang++ -std=c++17 \
		-I"cpp_core/include" \
		"cpp_core/src/mailcart.cpp" "cpp_core/src/mime_content.cpp" "cpp_core/src/outlook_mailcart.cpp" "cpp_core/src/outlook_client.cpp" "cpp_core/tests/outlook_integration_test.cpp" \
		-o ".build/outlook_integration_test"
	@".build/outlook_integration_test"

_shell-tests:
	@typeset -a SHELL_TESTS; \
	SHELL_TESTS=(); \
	for TEST_FILE in tests/sh/*.bats; do \
		if [ -f "$$TEST_FILE" ]; then \
			SHELL_TESTS+=("$$TEST_FILE"); \
		fi; \
	done; \
	if [ "$${#SHELL_TESTS[@]}" -gt 0 ]; then \
		bats "$${SHELL_TESTS[@]}"; \
	else \
		echo "No shell tests found."; \
	fi

_ui-regression:
	@printf '%s\n' \
		'from pathlib import Path' \
		'' \
		'checks = [' \
		'    ("load-more-label", Path("macos_app/UI/OutlookMailContentView.swift"), '\''Text("Load more emails")'\''),' \
		'    ("rendered-mode-html-view", Path("macos_app/UI/OutlookMailContentView.swift"), "HTMLBodyView(html: htmlBody)"),' \
		'    ("raw-body-renderer", Path("macos_app/UI/OutlookMailContentView.swift"), "private func rawBodyView(mailcart: OutlookMailcartDTO)"),' \
		'    ("split-view-layout", Path("macos_app/UI/OutlookMailContentView.swift"), "NavigationSplitView"),' \
		'    ("search-placeholder", Path("macos_app/UI/OutlookMailContentView.swift"), '\''TextField("Search Outlook mail", text: Binding('\''),' \
		'    ("navigation-title", Path("macos_app/UI/OutlookMailContentView.swift"), '\''.navigationTitle("Outlook")'\''),' \
		'    ("webkit-import", Path("macos_app/UI/HTMLBodyView.swift"), "import WebKit"),' \
		'    ("bridge-queue", Path("macos_app/UI/OutlookMailViewModel.swift"), '\''private let bridgeQueue = DispatchQueue(label: "mailcart.outlook-bridge-queue"'\''),' \
		'    ("read-off-main", Path("macos_app/UI/OutlookMailViewModel.swift"), "let result = await self.readMailcartFromBridge(messageId: messageId)"),' \
		'    ("search-off-main", Path("macos_app/UI/OutlookMailViewModel.swift"), "let result = await searchMailcartsFromBridge(query: queryAtRequestTime, cursor: cursor)"),' \
		']' \
		'' \
		'for check_name, file_path, expected in checks:' \
		'    source = file_path.read_text(encoding="utf-8")' \
		'    if expected not in source:' \
		'        raise SystemExit(f"UI regression failed ({check_name}): missing `{expected}` in {file_path}")' \
		'' \
		'print("Inline UI regression checks passed.")' \
	| python3

_ui-xcuitests:
	@if [ ! -d "$(XCUITEST_PROJECT)" ]; then \
		echo "❌ XCUITest project not found at $(XCUITEST_PROJECT)"; \
		exit 1; \
	fi
	@if ! command -v xcodebuild >/dev/null 2>&1; then \
		echo "❌ xcodebuild is required for macOS XCUITest regression suite."; \
		exit 1; \
	fi
	@typeset -a XCUITEST_METHODS XCUITEST_ARGS XCUITEST_SELECTED_NUMBERS XCUITEST_SELECTOR_TOKENS; \
	XCUITEST_METHODS=( \
		"testSearchFilterFindsFixtureRow" \
		"testLoadMoreAppendsFixtureRows" \
		"testSelectingSummaryLoadsFixtureDetail" \
		"testSortDetailAndBodyModesWorkInSingleLaunch" \
		"testSearchFieldAcceptsTyping" \
		"testLoadMoreButtonExistsAndCanBeTapped" \
		"testSummaryListIsVisible" \
	); \
	XCUITEST_ARGS=(); \
	XCUITEST_SELECTED_NUMBERS=(); \
	if [ -z "$${XCUITEST_SELECTOR:-}" ]; then \
		XCUITEST_ARGS+=("-only-testing:MailcartUITests"); \
	else \
		IFS=',' read -r -A XCUITEST_SELECTOR_TOKENS <<< "$${XCUITEST_SELECTOR}"; \
		for TOKEN in "$${XCUITEST_SELECTOR_TOKENS[@]}"; do \
			TOKEN="$${TOKEN//[[:space:]]/}"; \
			if [[ "$$TOKEN" =~ ^[0-9]+$$ ]]; then \
				START="$$TOKEN"; END="$$TOKEN"; \
			elif [[ "$$TOKEN" =~ ^([0-9]+)-([0-9]+)$$ ]]; then \
				START="$${match[1]}"; END="$${match[2]}"; \
				if [ "$$START" -gt "$$END" ]; then \
					echo "❌ Invalid XCUITEST_SELECTOR range '$$TOKEN' (start > end)."; \
					exit 1; \
				fi; \
			else \
				echo "❌ Invalid XCUITEST_SELECTOR token '$$TOKEN'. Expected N or N-M."; \
				exit 1; \
			fi; \
			for (( INDEX=START; INDEX<=END; INDEX++ )); do \
				if [ "$$INDEX" -lt 1 ] || [ "$$INDEX" -gt "$${#XCUITEST_METHODS[@]}" ]; then \
					echo "❌ Unknown UI regression test number '$$INDEX'. Valid range is 1-$${#XCUITEST_METHODS[@]}."; \
					exit 1; \
				fi; \
				if [[ " $${XCUITEST_SELECTED_NUMBERS[*]} " != *" $$INDEX "* ]]; then \
					XCUITEST_SELECTED_NUMBERS+=("$$INDEX"); \
				fi; \
			done; \
		done; \
		for INDEX in "$${XCUITEST_SELECTED_NUMBERS[@]}"; do \
			METHOD="$${XCUITEST_METHODS[$$((INDEX-1))]}"; \
			XCUITEST_ARGS+=("-only-testing:MailcartUITests/MailcartUITests/$$METHOD"); \
		done; \
	fi; \
	mkdir -p "$(XCUITEST_DERIVED_DATA_PATH)"; \
	xattr -dr com.apple.quarantine "$(XCUITEST_DERIVED_DATA_PATH)" >/dev/null 2>&1 || true; \
	xcodebuild test \
		-project "$(XCUITEST_PROJECT)" \
		-scheme "$(XCUITEST_SCHEME)" \
		-destination "$(XCUITEST_DESTINATION)" \
		-derivedDataPath "$(XCUITEST_DERIVED_DATA_PATH)" \
		"$${XCUITEST_ARGS[@]}"

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
		"macos_app/UI/HTMLBodyView.swift" \
		"macos_app/UI/UITestingSupport.swift" \
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
			macos_app/UI/HTMLBodyView.swift \
			macos_app/UI/UITestingSupport.swift \
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
	@semgrep scan --config auto --config ".semgrep.yml" --error .

#R125: Run SwiftLint as part of blocking make lint lane.
_lint_swiftlint:
	@if ! command -v swiftlint >/dev/null 2>&1; then \
		echo "swiftlint is required for make lint. Install swiftlint to continue."; \
		exit 1; \
	fi
	@swiftlint lint --strict --config ".swiftlint.yml"

#R126: Run Python-equivalent lint checks as part of make lint lane.
_lint_python_equivalent:
	@if ! command -v ruff >/dev/null 2>&1; then \
		echo "ruff is required for make lint. Install ruff to continue."; \
		exit 1; \
	fi
	@ruff check .

#R115: Run Bandit security checks for first-party repository Python sources.
_sast_bandit:
	@if ! command -v bandit >/dev/null 2>&1; then \
		echo "bandit is required for make sast. Install bandit to continue."; \
		exit 1; \
	fi
	@bandit -q -r "scripts" -x "mailcart-venv,.venv,venv,build,dist"

#R120: Run detect-secrets scan and fail when findings exist.
#R135: Ignore detect-secrets self-referential keyword findings in Makefile.
_sast_detect_secrets:
	@if ! command -v detect-secrets >/dev/null 2>&1; then \
		echo "detect-secrets is required for make sast. Install detect-secrets to continue."; \
		exit 1; \
	fi; \
	TMP_REPORT="$$(mktemp)"; \
	TRACKED_FILES="$$(git ls-files 2>/dev/null || true)"; \
	if [ -n "$$TRACKED_FILES" ]; then \
		detect-secrets scan $$TRACKED_FILES > "$$TMP_REPORT"; \
	else \
		detect-secrets scan --all-files > "$$TMP_REPORT"; \
	fi; \
	if python3 -c 'import json,pathlib,sys; payload=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")); results=payload.get("results",{}) if isinstance(payload,dict) else {}; findings=[(filename,entry) for filename,entries in results.items() if isinstance(entries,list) for entry in entries if isinstance(entry,dict)]; blocking=[(filename,entry) for filename,entry in findings if not (filename=="Makefile" and entry.get("type")=="Secret Keyword")]; [print("{}:{}: {}".format(filename, entry.get("line_number", "?"), entry.get("type", "<unknown>"))) for filename,entry in blocking]; raise SystemExit(1 if blocking else 0)' "$$TMP_REPORT"; then \
		rm -f "$$TMP_REPORT"; \
	else \
		echo "detect-secrets findings detected."; \
		rm -f "$$TMP_REPORT"; \
		exit 1; \
	fi

#R060: Run clang-tidy on C++ and bridge Objective-C(++) sources for make lint.
#R075: Enforce blocking clang-tidy configuration for lint lane.
_sast_clang_tidy:
	@CLANG_TIDY_BIN="$$(command -v clang-tidy 2>/dev/null || true)"; \
	if [ -z "$$CLANG_TIDY_BIN" ]; then \
		LLVM_PREFIX="$$(brew --prefix llvm 2>/dev/null || true)"; \
		if [ -n "$$LLVM_PREFIX" ] && [ -x "$$LLVM_PREFIX/bin/clang-tidy" ]; then \
			CLANG_TIDY_BIN="$$LLVM_PREFIX/bin/clang-tidy"; \
		fi; \
	fi; \
	if [ -z "$$CLANG_TIDY_BIN" ]; then \
		echo "clang-tidy is required for make lint. Install prerequisites with ./01_install_prerequisites.sh"; \
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
	fi; \
	if python3 -c 'import pathlib,re,sys; text=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace"); pattern=re.compile(r"Suppressed [1-9][0-9]* warnings"); raise SystemExit(0 if pattern.search(text) else 1)' "$$CLANG_TIDY_LOG"; then \
		echo "clang-tidy suppressed warnings detected. See $$CLANG_TIDY_LOG."; \
		exit 1; \
	fi

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
