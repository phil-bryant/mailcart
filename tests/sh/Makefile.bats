#!/usr/bin/env bats

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  export REPO_ROOT
  export MAKEFILE_PATH="${REPO_ROOT}/Makefile"
  export TLS_INSTALLER_PATH="${REPO_ROOT}/04_install_matchy_api_tls.sh"
  export SWIFTLINT_CONFIG_PATH="${REPO_ROOT}/.swiftlint.yml"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export SANDBOX="${TMP_ROOT}/sandbox"
  export STUB_BIN="${TMP_ROOT}/bin"
  export TEST_LOG="${TMP_ROOT}/commands.log"
  mkdir -p "${SANDBOX}" "${STUB_BIN}"
  cp "${MAKEFILE_PATH}" "${SANDBOX}/Makefile"
  cp "${TLS_INSTALLER_PATH}" "${SANDBOX}/04_install_matchy_api_tls.sh"
  cp "${SWIFTLINT_CONFIG_PATH}" "${SANDBOX}/.swiftlint.yml"
  chmod +x "${SANDBOX}/04_install_matchy_api_tls.sh"
  : > "${TEST_LOG}"
}

teardown() {
  rm -rf "${TMP_ROOT}"
}

run_make() {
  run env PATH="${STUB_BIN}:/usr/bin:/bin" make -C "${SANDBOX}" "$@"
}

create_compiler_stub() {
  cat > "${STUB_BIN}/clang++" <<'EOF'
#!/bin/bash
printf "clang++ %s\n" "$*" >> "${TEST_LOG}"
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then
    out="$arg"
  fi
  prev="$arg"
done
if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")"
  cat > "$out" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "$out"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/clang++"
}

create_xcrun_stub() {
  cat > "${STUB_BIN}/xcrun" <<'EOF'
#!/bin/bash
printf "xcrun %s\n" "$*" >> "${TEST_LOG}"
if [ "$1" = "--sdk" ] && [ "$2" = "macosx" ] && [ "$3" = "--show-sdk-path" ]; then
  echo "/tmp/fake-macos-sdk"
  exit 0
fi
if [ "$1" = "swiftc" ]; then
  exit 0
fi
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then
    out="$arg"
  fi
  prev="$arg"
done
if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")"
  : > "$out"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/xcrun"
}

create_xcode_stubs() {
  cat > "${STUB_BIN}/xcodegen" <<'EOF'
#!/bin/bash
printf "xcodegen %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodegen"

  cat > "${STUB_BIN}/xcodebuild" <<'EOF'
#!/bin/bash
printf "xcodebuild %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
}

create_open_stub() {
  cat > "${STUB_BIN}/open" <<'EOF'
#!/bin/bash
printf "open %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/open"
}

create_1psa_stub() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/bin/bash
printf "1psa %s\n" "$*" >> "${TEST_LOG}"
if [ "$1" = "-f" ]; then
  echo "fake-graph-token"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
}

create_ps_stub_alive() {
  cat > "${STUB_BIN}/ps" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/ps"
}

create_ps_stub_dead() {
  cat > "${STUB_BIN}/ps" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "${STUB_BIN}/ps"
}

create_kill_stub() {
  cat > "${STUB_BIN}/kill" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/kill"
}

create_all_stubs() {
  create_compiler_stub
  create_xcrun_stub
  create_xcode_stubs
  create_open_stub
}

create_bats_stub() {
  cat > "${STUB_BIN}/bats" <<'EOF'
#!/bin/bash
printf "bats %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/bats"
}

create_ui_regression_source_fixtures() {
  mkdir -p "${SANDBOX}/macos_app/UI"
  cat > "${SANDBOX}/macos_app/UI/OutlookMailContentView.swift" <<'EOF'
import SwiftUI

struct OutlookMailContentView: View {
  var body: some View {
    NavigationSplitView {
      Text("Load more emails")
      TextField("Search Outlook mail", text: Binding(
        get: { "" },
        set: { _ in }
      ))
      HTMLBodyView(html: htmlBody)
    } detail: {
      Text("detail")
    }
    .navigationTitle("Outlook")
  }

  private let htmlBody = "<html></html>"

  private func rawBodyView(mailcart: OutlookMailcartDTO) -> some View {
    Text("raw")
  }
}

struct OutlookMailcartDTO {}
EOF

  cat > "${SANDBOX}/macos_app/UI/HTMLBodyView.swift" <<'EOF'
import WebKit
import SwiftUI

struct HTMLBodyView: View {
  let html: String
  var body: some View {
    Text(html)
  }
}
EOF

  cat > "${SANDBOX}/macos_app/UI/OutlookMailViewModel.swift" <<'EOF'
import Foundation

final class OutlookMailViewModel {
  private let bridgeQueue = DispatchQueue(label: "mailcart.outlook-bridge-queue")

  func read(messageId: String, queryAtRequestTime: String, cursor: String?) async {
    // let result = await self.readMailcartFromBridge(messageId: messageId)
    let selected = await self.readMailcartFromBridge(messageId: messageId)
    // let result = await searchMailcartsFromBridge(query: queryAtRequestTime, cursor: cursor)
    let result = await searchMailcartsFromBridge(query: queryAtRequestTime, cursor: cursor)
    _ = selected
    _ = result
  }

  private func readMailcartFromBridge(messageId: String) async -> String { messageId }
  private func searchMailcartsFromBridge(query: String, cursor: String?) async -> String { query }
}
EOF
}

create_shellcheck_stub() {
  cat > "${STUB_BIN}/shellcheck" <<'EOF'
#!/bin/bash
printf "shellcheck argc=%s" "$#" >> "${TEST_LOG}"
for arg in "$@"; do
  printf " [%s]" "$arg" >> "${TEST_LOG}"
done
printf "\n" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/shellcheck"
}

create_semgrep_stub() {
  cat > "${STUB_BIN}/semgrep" <<'EOF'
#!/bin/bash
printf "semgrep %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/semgrep"
}

create_clang_tidy_stub() {
  cat > "${STUB_BIN}/clang-tidy" <<'EOF'
#!/bin/bash
printf "clang-tidy %s\n" "$*" >> "${TEST_LOG}"
if [ "${CLANG_TIDY_EMIT_ERROR:-0}" -ne 0 ]; then
  echo "fake.cpp:1:1: error: simulated blocking finding [bugprone-test,-warnings-as-errors]"
fi
if [ "${CLANG_TIDY_SUPPRESSED_WARNINGS:-0}" -ne 0 ]; then
  echo "Suppressed 1 warnings (1 NOLINT)."
fi
if [ "${CLANG_TIDY_EXIT_CODE:-0}" -ne 0 ]; then
  exit "${CLANG_TIDY_EXIT_CODE}"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/clang-tidy"
}

create_ruff_stub() {
  cat > "${STUB_BIN}/ruff" <<'EOF'
#!/bin/bash
printf "ruff %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/ruff"
}

create_swiftlint_stub() {
  cat > "${STUB_BIN}/swiftlint" <<'EOF'
#!/bin/bash
printf "swiftlint %s\n" "$*" >> "${TEST_LOG}"
if [ "${SWIFTLINT_EMIT_WARNING:-0}" -ne 0 ]; then
  echo "warning: simulated swiftlint warning finding"
  if [ "$1" = "lint" ] && [ "$2" = "--strict" ]; then
    exit 2
  fi
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/swiftlint"
}

create_bandit_stub() {
  cat > "${STUB_BIN}/bandit" <<'EOF'
#!/bin/bash
printf "bandit %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/bandit"
}

create_detect_secrets_stub() {
  cat > "${STUB_BIN}/detect-secrets" <<'EOF'
#!/bin/bash
printf "detect-secrets %s\n" "$*" >> "${TEST_LOG}"
if [ "${DETECT_SECRETS_EMIT_MAKEFILE_KEYWORD_FINDINGS:-0}" -ne 0 ]; then
  echo '{"results":{"Makefile":[{"type":"Secret Keyword","line_number":335},{"type":"Secret Keyword","line_number":346}]}}'
elif [ "${DETECT_SECRETS_EMIT_FINDINGS:-0}" -ne 0 ]; then
  echo '{"results":{"fixture.py":[{"type":"Secret Keyword","line_number":1}]}}'
else
  echo '{"results":{}}'
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/detect-secrets"
}

create_git_ls_files_stub() {
  cat > "${STUB_BIN}/git" <<'EOF'
#!/bin/bash
if [ "$1" = "ls-files" ]; then
  printf "Makefile\n"
  printf "05_run_all_tests_parallel.sh\n"
  printf "01_install_prerequisites.sh\n"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/git"
}

create_clamscan_stub() {
  cat > "${STUB_BIN}/clamscan" <<'EOF'
#!/bin/bash
printf "clamscan %s\n" "$*" >> "${TEST_LOG}"
infected="${CLAMSCAN_STUB_INFECTED_FILES:-0}"
log_path=""
for arg in "$@"; do
  case "$arg" in
    --log=*)
      log_path="${arg#--log=}"
      ;;
  esac
done
summary="$(cat <<INNER
----------- SCAN SUMMARY -----------
Infected files: ${infected}
INNER
)"
printf "%s\n" "$summary"
if [ -n "$log_path" ]; then
  printf "%s\n" "$summary" > "$log_path"
fi
if [ "${infected}" -gt 0 ]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/clamscan"
}

create_gitleaks_stub() {
  cat > "${STUB_BIN}/gitleaks" <<'EOF'
#!/bin/bash
printf "gitleaks %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/gitleaks"
}

create_python3_stub() {
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/bin/bash
if [ "$1" = "-c" ]; then
  /usr/bin/python3 "$@"
  exit $?
fi
printf "python3 %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/python3"
}

create_bash_stub() {
  cat > "${STUB_BIN}/bash" <<'EOF'
#!/bin/bash
printf "bash %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/bash"
}

@test "R001: help target documents consolidated workflow targets" {
  #R001
  run_make help
  [ "$status" -eq 0 ]
  [[ "${output}" == *"make lint"* ]]
  [[ "${output}" == *"make build"* ]]
  [[ "${output}" == *"make test"* ]]
  [[ "${output}" == *"make ui-test"* ]]
  [[ "${output}" == *"make crash"* ]]
  [[ "${output}" == *"make run-ui"* ]]
  [[ "${output}" == *"make sast"* ]]
  [[ "${output}" == *"make clam"* ]]
  [[ "${output}" == *"make run-api"* ]]
  [[ "${output}" == *"make clean"* ]]
}

@test "R045,R050,R055,R065,R115,R120: sast runs shell, semgrep, bandit, detect-secrets, and gitleaks" {
  #R045 #R050 #R055 #R065 #R115 #R120
  create_shellcheck_stub
  create_semgrep_stub
  create_bandit_stub
  create_detect_secrets_stub
  create_git_ls_files_stub
  create_gitleaks_stub
  : > "${SANDBOX}/05_run_all_tests_parallel.sh"
  : > "${SANDBOX}/01_install_prerequisites.sh"

  run_make sast
  [ "$status" -eq 0 ]
  [[ "${output}" == *"✅ SAST checks completed with no findings."* ]]
  run rg "^shellcheck argc=[0-9]+ " "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "\\[01_install_prerequisites.sh\\]" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "\\[05_run_all_tests_parallel.sh\\]" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^semgrep +scan --config auto --config \.semgrep.yml --error \.$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^bandit +-q +-r scripts +-x mailcart-venv,.venv,venv,build,dist$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^detect-secrets +scan .+" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^detect-secrets +scan .*Makefile" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^detect-secrets +scan .*--all-files" "${TEST_LOG}"
  [ "$status" -ne 0 ]
  run rg "^gitleaks +detect --source \. --config \.gitleaks.toml --no-banner --redact --exit-code 1$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R085: sast prints per-tool headers before each security tool" {
  #R085
  create_shellcheck_stub
  create_semgrep_stub
  create_bandit_stub
  create_detect_secrets_stub
  create_git_ls_files_stub
  create_gitleaks_stub
  : > "${SANDBOX}/05_run_all_tests_parallel.sh"
  : > "${SANDBOX}/01_install_prerequisites.sh"

  run_make sast
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Security Tool: ShellCheck"* ]]
  [[ "${output}" == *"Security Tool: Semgrep"* ]]
  [[ "${output}" == *"Security Tool: Bandit"* ]]
  [[ "${output}" == *"Security Tool: detect-secrets"* ]]
  [[ "${output}" == *"Security Tool: Gitleaks"* ]]
  [[ "${output}" == *"URL: https://www.shellcheck.net/"* ]]
  [[ "${output}" == *"URL: https://semgrep.dev/docs/"* ]]
  [[ "${output}" == *"URL: https://bandit.readthedocs.io/"* ]]
  [[ "${output}" == *"URL: https://github.com/Yelp/detect-secrets"* ]]
  [[ "${output}" == *"URL: https://github.com/gitleaks/gitleaks"* ]]
}

@test "R090: sast prints per-tool running notifications before each security tool" {
  #R090
  create_shellcheck_stub
  create_semgrep_stub
  create_bandit_stub
  create_detect_secrets_stub
  create_git_ls_files_stub
  create_gitleaks_stub
  : > "${SANDBOX}/05_run_all_tests_parallel.sh"
  : > "${SANDBOX}/01_install_prerequisites.sh"

  run_make sast
  [ "$status" -eq 0 ]
  [[ "${output}" == *"▶ Running ShellCheck..."* ]]
  [[ "${output}" == *"▶ Running Semgrep..."* ]]
  [[ "${output}" == *"▶ Running Bandit..."* ]]
  [[ "${output}" == *"▶ Running detect-secrets..."* ]]
  [[ "${output}" == *"▶ Running gitleaks..."* ]]
}

@test "R060,R070,R125,R126: lint runs blocking clang-tidy checks and emits success marker" {
  #R060 #R070 #R125 #R126
  create_clang_tidy_stub
  create_xcrun_stub
  create_swiftlint_stub
  create_ruff_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" make -C "${SANDBOX}" lint
  [ "$status" -eq 0 ]
  [[ "${output}" == *"✅ lint checks completed with no findings."* ]]
  run rg "^clang-tidy +--config-file=.clang-tidy +cpp_core/src/mailcart.cpp" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^xcrun +--sdk macosx .*/clang-tidy .*--config-file=.clang-tidy .*macos_app/Bridge/OutlookClientBridge.mm" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg '^swiftlint +lint --strict --config \.swiftlint\.yml$' "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^ruff +check \.$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R125: lint fails with red X when swiftlint reports warning findings" {
  #R125
  create_clang_tidy_stub
  create_xcrun_stub
  create_swiftlint_stub
  create_ruff_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" SWIFTLINT_EMIT_WARNING=1 make -C "${SANDBOX}" lint
  [ "$status" -ne 0 ]
  [[ "${output}" == *"warning: simulated swiftlint warning finding"* ]]
  [[ "${output}" == *"❌ lint checks completed with findings or failures."* ]]
}

@test "R125: swiftlint config excludes generated dependency source trees" {
  #R125
  run rg '^excluded:$' "${SANDBOX}/.swiftlint.yml"
  [ "$status" -eq 0 ]
  run rg '^\s*-\s+\.build$' "${SANDBOX}/.swiftlint.yml"
  [ "$status" -eq 0 ]
  run rg '^\s*-\s+"\*\*/DerivedData"$' "${SANDBOX}/.swiftlint.yml"
  [ "$status" -eq 0 ]
  run rg '^\s*-\s+"\*\*/SourcePackages"$' "${SANDBOX}/.swiftlint.yml"
  [ "$status" -eq 0 ]
}

@test "R045,R120: sast fails and prints red X when detect-secrets finds secrets" {
  #R045 #R120
  create_shellcheck_stub
  create_semgrep_stub
  create_bandit_stub
  create_detect_secrets_stub
  create_git_ls_files_stub
  create_gitleaks_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" DETECT_SECRETS_EMIT_FINDINGS=1 make -C "${SANDBOX}" sast
  [ "$status" -ne 0 ]
  [[ "${output}" == *"detect-secrets findings detected."* ]]
  [[ "${output}" == *"❌ SAST checks completed with findings or failures."* ]]
}

@test "R135: sast ignores detect-secrets keyword-only findings in Makefile" {
  #R135
  create_shellcheck_stub
  create_semgrep_stub
  create_bandit_stub
  create_detect_secrets_stub
  create_git_ls_files_stub
  create_gitleaks_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" DETECT_SECRETS_EMIT_MAKEFILE_KEYWORD_FINDINGS=1 make -C "${SANDBOX}" sast
  [ "$status" -eq 0 ]
  [[ "${output}" == *"✅ SAST checks completed with no findings."* ]]
}

@test "R060: lint fails with red X when clang-tidy reports suppressed warnings" {
  #R060
  create_clang_tidy_stub
  create_xcrun_stub
  create_swiftlint_stub
  create_ruff_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" CLANG_TIDY_SUPPRESSED_WARNINGS=1 make -C "${SANDBOX}" lint
  [ "$status" -ne 0 ]
  [[ "${output}" == *"clang-tidy suppressed warnings detected."* ]]
  [[ "${output}" == *"❌ lint checks completed with findings or failures."* ]]
}

@test "R075: clang-tidy uses blocking config for lint lane" {
  #R075
  create_clang_tidy_stub
  create_xcrun_stub
  create_swiftlint_stub
  create_ruff_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" make -C "${SANDBOX}" lint
  [ "$status" -eq 0 ]
  run rg "^clang-tidy +--config-file=.clang-tidy +cpp_core/src/mailcart.cpp" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^xcrun +--sdk macosx .*/clang-tidy .*--config-file=.clang-tidy .*macos_app/Bridge/OutlookClientBridge.mm" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R130: make clam runs ClamAV recursively on repository" {
  #R130
  create_clamscan_stub
  run_make clam
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Infected files: 0"* ]]
  [[ "${output}" == *"✅ clam scan completed with no findings."* ]]
  run rg "^clamscan +-r \. +--log=.+" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R140: make clam prints red X when infected files are found" {
  #R140
  create_clamscan_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" CLAMSCAN_STUB_INFECTED_FILES=2 make -C "${SANDBOX}" clam
  [ "$status" -ne 0 ]
  [[ "${output}" == *"Infected files: 2"* ]]
  [[ "${output}" == *"❌ clam scan completed with findings or failures."* ]]
}

@test "R005: test target runs C++ integration and all shell tests" {
  #R005
  create_compiler_stub
  create_python3_stub
  create_bats_stub
  mkdir -p "${SANDBOX}/tests/sh"
  mkdir -p "${SANDBOX}/tests/python"
  : > "${SANDBOX}/tests/sh/mailcart.bats"
  : > "${SANDBOX}/tests/sh/Bridge.bats"
  : > "${SANDBOX}/tests/sh/UI.bats"
  : > "${SANDBOX}/tests/python/test_matchy_mailcart_api.py"
  run_make test
  [ "$status" -eq 0 ]
  [ -x "${SANDBOX}/.build/outlook_integration_test" ]
  run rg "clang\+\+ -std=c\+\+17" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^python3 -m unittest discover -s tests/python -p test_\\*\\.py$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "bats +tests/sh/Bridge.bats tests/sh/UI.bats tests/sh/mailcart.bats" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R010,R015,R020,R025: build runs bridge check, typecheck, and app rebuild/reuse flow" {
  #R010 #R015 #R020 #R025
  local app_bundle="${SANDBOX}/app/Mailcart.app"
  local app_executable="${app_bundle}/Contents/MacOS/Mailcart"
  create_all_stubs

  run_make build APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}" PROJECT_FILE="${SANDBOX}/Generated.xcodeproj" UI_BUILD_DIR="${SANDBOX}/ui" DERIVED_DATA="${SANDBOX}/ui/DerivedData"
  [ "$status" -eq 0 ]
  [ -f "${SANDBOX}/.build/OutlookClientBridge.o" ]
  [ -f "${SANDBOX}/.build/OutlookBridgeModels.o" ]
  run rg "xcrun swiftc -typecheck" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "macos_app/UI/HTMLBodyView.swift" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "macos_app/UI/HTMLBodyView.swift" "${SANDBOX}/Makefile"
  [ "$status" -eq 0 ]
  run rg "xcodegen generate --spec macos_app/project.yml" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "xcodebuild -project ${SANDBOX}/Generated.xcodeproj" "${TEST_LOG}"
  [ "$status" -eq 0 ]

  mkdir -p "$(dirname "${app_executable}")"
  cat > "${app_executable}" <<'EOF'
#!/bin/bash
sleep 10
EOF
  chmod +x "${app_executable}"
  : > "${TEST_LOG}"

  run_make build APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}" PROJECT_FILE="${SANDBOX}/Generated.xcodeproj" UI_BUILD_DIR="${SANDBOX}/ui" DERIVED_DATA="${SANDBOX}/ui/DerivedData"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Using existing build at ${app_bundle}"* ]]
  run rg "xcodebuild" "${TEST_LOG}"
  [ "$status" -ne 0 ]
}

@test "R030: run resolves graph token via 1psa and launches app executable" {
  #R030
  local app_bundle="${SANDBOX}/app/Mailcart.app"
  local app_executable="${STUB_BIN}/app-runner"
  create_all_stubs
  create_1psa_stub
  cat > "${app_executable}" <<'EOF'
#!/bin/bash
printf "app-runner token=%s\n" "${OUTLOOK_GRAPH_TOKEN}" >> "${TEST_LOG}"
EOF
  chmod +x "${app_executable}"

  run_make run APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}" PROJECT_FILE="${SANDBOX}/Generated.xcodeproj"
  [ "$status" -eq 0 ]
  run rg "^1psa -f OUTLOOK_GRAPH_API token$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R035: ui-test executes inline UI regression lane and smoke verification" {
  #R035
  local app_bundle="${SANDBOX}/app/Mailcart.app"
  local app_executable="${app_bundle}/Contents/MacOS/Mailcart"
  create_kill_stub
  create_xcode_stubs
  create_ui_regression_source_fixtures
  mkdir -p "${SANDBOX}/macos_app/Mailcart.xcodeproj"
  mkdir -p "${SANDBOX}/tests/sh"
  mkdir -p "${SANDBOX}/scripts"
  mkdir -p "$(dirname "${app_executable}")"
  : > "${SANDBOX}/tests/sh/UI.bats"
  cat > "${app_executable}" <<'EOF'
#!/bin/bash
sleep 10
EOF
  chmod +x "${app_executable}"
  create_ps_stub_alive
  run_make ui-test APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Running inline UI regression checks"* ]]
  [[ "${output}" == *"Inline UI regression checks passed."* ]]
  [[ "${output}" == *"Running macOS XCUITest regression suite"* ]]
  [[ "${output}" == *"Running UI smoke launch check"* ]]
  [[ "${output}" == *"smoke test passed"* ]]
  [[ "${output}" != *"Skipping PLCrashReporter smoke verification"* ]]
  run rg "xcodebuild test" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "bats tests/sh/UI.bats" "${TEST_LOG}"
  [ "$status" -ne 0 ]

  cat > "${app_executable}" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${app_executable}"
  create_ps_stub_dead
  run_make ui-test APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"UI process exited before smoke timeout."* ]]
}

@test "R080: crash-reporter smoke lane is available directly and through ui-test toggle" {
  #R080
  local app_bundle="${SANDBOX}/app/Mailcart.app"
  local app_executable="${app_bundle}/Contents/MacOS/Mailcart"
  create_kill_stub
  create_xcode_stubs
  create_ui_regression_source_fixtures
  mkdir -p "${SANDBOX}/macos_app/Mailcart.xcodeproj"
  mkdir -p "${SANDBOX}/tests/sh"
  mkdir -p "${SANDBOX}/scripts"
  mkdir -p "$(dirname "${app_executable}")"
  : > "${SANDBOX}/tests/sh/UI.bats"
  cat > "${app_executable}" <<'EOF'
#!/bin/bash
sleep 10
EOF
  chmod +x "${app_executable}"
  create_ps_stub_alive
  cat > "${SANDBOX}/scripts/verify_macos_crash_reporter.sh" <<'EOF'
#!/bin/bash
printf "crash-smoke-script\n" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${SANDBOX}/scripts/verify_macos_crash_reporter.sh"

  run_make crash-reporter-smoke APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}"
  [ "$status" -eq 0 ]
  run rg "crash-smoke-script" "${TEST_LOG}"
  [ "$status" -eq 0 ]

  : > "${TEST_LOG}"
  run_make ui-test RUN_CRASH_REPORTER_SMOKE_TEST=true APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Running PLCrashReporter smoke verification"* ]]
  run rg "crash-smoke-script" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R095,R100: make exposes script-backed Matchy API and crash lanes" {
  #R095 #R100 #R030 #R070
  local app_bundle="${SANDBOX}/app/Mailcart.app"
  local app_executable="${app_bundle}/Contents/MacOS/Mailcart"
  create_python3_stub
  create_bash_stub
  create_1psa_stub
  create_clang_tidy_stub
  create_swiftlint_stub
  create_ruff_stub
  create_xcrun_stub
  create_ps_stub_alive
  create_kill_stub
  mkdir -p "${SANDBOX}/scripts"
  mkdir -p "$(dirname "${app_executable}")"
  cat > "${app_executable}" <<'EOF'
#!/bin/bash
sleep 10
EOF
  chmod +x "${app_executable}"
  cat > "${SANDBOX}/scripts/verify_macos_crash_reporter.sh" <<'EOF'
#!/bin/bash
printf "crash-smoke-script\n" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${SANDBOX}/scripts/verify_macos_crash_reporter.sh"

  run_make run-api
  [ "$status" -eq 0 ]
  run rg "^bash .+/04_install_matchy_api_tls\.sh$" "${TEST_LOG}" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^python3 .+/scripts/matchy_mailcart_api\.py$" "${TEST_LOG}" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  rm -f "${STUB_BIN}/bash"

  run_make verify-macos-crash-reporter APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}"
  [ "$status" -eq 0 ]
  run_make crash APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}"
  [ "$status" -eq 0 ]
  run_make run-ui APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}" PROJECT_FILE="${SANDBOX}/Generated.xcodeproj"
  [ "$status" -eq 0 ]
  run_make lint
  [ "$status" -eq 0 ]
  run rg "^crash-smoke-script$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^1psa -f OUTLOOK_GRAPH_API token$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^clang-tidy +--config-file=.clang-tidy +cpp_core/src/mailcart.cpp" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R040: clean target removes sandbox build outputs, generated project file, and profraw artifact" {
  #R040
  mkdir -p "${SANDBOX}/.build"
  : > "${SANDBOX}/.build/artifact.tmp"
  : > "${SANDBOX}/Generated.xcodeproj"
  : > "${SANDBOX}/default.profraw"

  run_make clean PROJECT_FILE="${SANDBOX}/Generated.xcodeproj"
  [ "$status" -eq 0 ]
  [ ! -e "${SANDBOX}/.build/artifact.tmp" ]
  [ ! -e "${SANDBOX}/Generated.xcodeproj" ]
  [ ! -e "${SANDBOX}/default.profraw" ]
}
