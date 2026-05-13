#!/usr/bin/env bats

setup() {
  export REPO_ROOT="/Users/phil/local/src/mailcart"
  export MAKEFILE_PATH="${REPO_ROOT}/Makefile"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export SANDBOX="${TMP_ROOT}/sandbox"
  export STUB_BIN="${TMP_ROOT}/bin"
  export TEST_LOG="${TMP_ROOT}/commands.log"
  mkdir -p "${SANDBOX}" "${STUB_BIN}"
  cp "${MAKEFILE_PATH}" "${SANDBOX}/Makefile"
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
if [ "${CLANG_TIDY_EXIT_CODE:-0}" -ne 0 ]; then
  exit "${CLANG_TIDY_EXIT_CODE}"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/clang-tidy"
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
printf "python3 %s\n" "$*" >> "${TEST_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/python3"
}

@test "R001: help target documents consolidated workflow targets" {
  #R001
  run_make help
  [ "$status" -eq 0 ]
  [[ "${output}" == *"make build"* ]]
  [[ "${output}" == *"make test"* ]]
  [[ "${output}" == *"make ui-test"* ]]
  [[ "${output}" == *"make run"* ]]
  [[ "${output}" == *"make crash-reporter-smoke"* ]]
  [[ "${output}" == *"make sast"* ]]
  [[ "${output}" == *"make sast-report"* ]]
  [[ "${output}" == *"make clean"* ]]
}

@test "R045,R050,R055,R060,R065: sast runs shell, semgrep, clang-tidy, and secret scanning" {
  #R045 #R050 #R055 #R060 #R065
  create_shellcheck_stub
  create_semgrep_stub
  create_clang_tidy_stub
  create_gitleaks_stub
  create_xcrun_stub
  : > "${SANDBOX}/00_verify_requirements_traceability.sh"
  : > "${SANDBOX}/01_install_prerequisites.sh"

  run_make sast
  [ "$status" -eq 0 ]
  [[ "${output}" == *"SAST checks completed."* ]]
  run rg "^shellcheck argc=2 " "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "\\[01_install_prerequisites.sh\\]" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "\\[00_verify_requirements_traceability.sh\\]" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^semgrep +--config auto --config \.semgrep.yml --error --quiet \.$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^clang-tidy +--config-file=.clang-tidy +cpp_core/src/mailcart.cpp" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^xcrun +--sdk macosx .*/clang-tidy .*--config-file=.clang-tidy .*macos_app/Bridge/OutlookClientBridge.mm" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^gitleaks +detect --source \. --config \.gitleaks.toml --no-banner --redact --exit-code 1$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R085: sast prints per-tool headers before each security tool" {
  #R085
  create_shellcheck_stub
  create_semgrep_stub
  create_clang_tidy_stub
  create_gitleaks_stub
  create_xcrun_stub
  : > "${SANDBOX}/00_verify_requirements_traceability.sh"
  : > "${SANDBOX}/01_install_prerequisites.sh"

  run_make sast
  [ "$status" -eq 0 ]
  [[ "${output}" == *"┌──── ShellCheck ────┐"* ]]
  [[ "${output}" == *"┌──── Semgrep ────┐"* ]]
  [[ "${output}" == *"┌──── clang-tidy ────┐"* ]]
  [[ "${output}" == *"┌──── gitleaks ────┐"* ]]
}

@test "R090: sast prints per-tool running notifications before each security tool" {
  #R090
  create_shellcheck_stub
  create_semgrep_stub
  create_clang_tidy_stub
  create_gitleaks_stub
  create_xcrun_stub
  : > "${SANDBOX}/00_verify_requirements_traceability.sh"
  : > "${SANDBOX}/01_install_prerequisites.sh"

  run_make sast
  [ "$status" -eq 0 ]
  [[ "${output}" == *"▶ Running ShellCheck..."* ]]
  [[ "${output}" == *"▶ Running Semgrep..."* ]]
  [[ "${output}" == *"▶ Running clang-tidy..."* ]]
  [[ "${output}" == *"▶ Running gitleaks..."* ]]
}

@test "R070,R075: sast-report runs non-blocking clang-tidy report config" {
  #R070 #R075
  create_clang_tidy_stub
  create_xcrun_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" CLANG_TIDY_EXIT_CODE=1 make -C "${SANDBOX}" sast-report
  [ "$status" -eq 0 ]
  [[ "${output}" == *"SAST report checks completed."* ]]
  run rg "^clang-tidy +--config-file=.clang-tidy.report +cpp_core/src/mailcart.cpp" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "^xcrun +--sdk macosx .*/clang-tidy .*--config-file=.clang-tidy.report .*macos_app/Bridge/OutlookClientBridge.mm" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R060: sast fails when blocking clang-tidy findings are present" {
  #R060
  create_shellcheck_stub
  create_semgrep_stub
  create_clang_tidy_stub
  create_gitleaks_stub
  create_xcrun_stub
  : > "${SANDBOX}/00_verify_requirements_traceability.sh"
  : > "${SANDBOX}/01_install_prerequisites.sh"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" CLANG_TIDY_EMIT_ERROR=1 make -C "${SANDBOX}" sast
  [ "$status" -ne 0 ]
  [[ "${output}" == *"clang-tidy blocking findings detected."* ]]
}

@test "R005: test target runs C++ integration and non-UI shell tests" {
  #R005
  create_compiler_stub
  create_bats_stub
  mkdir -p "${SANDBOX}/tests/sh"
  : > "${SANDBOX}/tests/sh/mailcart.bats"
  : > "${SANDBOX}/tests/sh/Bridge.bats"
  : > "${SANDBOX}/tests/sh/UI.bats"
  run_make test
  [ "$status" -eq 0 ]
  [ -x "${SANDBOX}/.build/outlook_integration_test" ]
  run rg "clang\+\+ -std=c\+\+17" "${TEST_LOG}"
  [ "$status" -eq 0 ]
  run rg "bats +tests/sh/Bridge.bats tests/sh/mailcart.bats" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R010,R015,R020,R025: build runs bridge check, typecheck, and app rebuild/reuse flow" {
  #R010 #R015 #R020 #R025
  local app_bundle="${SANDBOX}/app/OutlookMailApp.app"
  local app_executable="${app_bundle}/Contents/MacOS/OutlookMailApp"
  create_all_stubs

  run_make build APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}" PROJECT_FILE="${SANDBOX}/Generated.xcodeproj" UI_BUILD_DIR="${SANDBOX}/ui" DERIVED_DATA="${SANDBOX}/ui/DerivedData"
  [ "$status" -eq 0 ]
  [ -f "${SANDBOX}/.build/OutlookClientBridge.o" ]
  [ -f "${SANDBOX}/.build/OutlookBridgeModels.o" ]
  run rg "xcrun swiftc -typecheck" "${TEST_LOG}"
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
  local app_bundle="${SANDBOX}/app/OutlookMailApp.app"
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
  run rg "^1psa -f outlook_graph_token password$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R035: ui-test executes UI bats lane and smoke verification" {
  #R035
  local app_bundle="${SANDBOX}/app/OutlookMailApp.app"
  local app_executable="${app_bundle}/Contents/MacOS/OutlookMailApp"
  create_bats_stub
  create_kill_stub
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
  [[ "${output}" == *"smoke test passed"* ]]
  [[ "${output}" == *"Skipping PLCrashReporter smoke verification"* ]]
  run rg "bats tests/sh/UI.bats" "${TEST_LOG}"
  [ "$status" -eq 0 ]

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
  local app_bundle="${SANDBOX}/app/OutlookMailApp.app"
  local app_executable="${app_bundle}/Contents/MacOS/OutlookMailApp"
  create_bats_stub
  create_kill_stub
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

@test "R095,R100: make exposes script-backed Matchy and crash alias lanes" {
  #R095 #R100
  local app_bundle="${SANDBOX}/app/OutlookMailApp.app"
  local app_executable="${app_bundle}/Contents/MacOS/OutlookMailApp"
  create_python3_stub
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

  run_make run-matchy-api
  [ "$status" -eq 0 ]
  run_make matchy-mailcart-api
  [ "$status" -eq 0 ]
  run rg "^python3 scripts/matchy_mailcart_api.py$" "${TEST_LOG}" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "2" ]

  run_make verify-macos-crash-reporter APP_BUNDLE="${app_bundle}" APP_EXECUTABLE="${app_executable}"
  [ "$status" -eq 0 ]
  run rg "^crash-smoke-script$" "${TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "R040: clean target removes sandbox build outputs and generated project file" {
  #R040
  mkdir -p "${SANDBOX}/.build"
  : > "${SANDBOX}/.build/artifact.tmp"
  : > "${SANDBOX}/Generated.xcodeproj"

  run_make clean PROJECT_FILE="${SANDBOX}/Generated.xcodeproj"
  [ "$status" -eq 0 ]
  [ ! -e "${SANDBOX}/.build/artifact.tmp" ]
  [ ! -e "${SANDBOX}/Generated.xcodeproj" ]
}
