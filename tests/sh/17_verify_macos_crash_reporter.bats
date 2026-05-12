#!/usr/bin/env bats

setup() {
  export REPO_ROOT="/Users/phil/local/src/mailcart"
  export SCRIPT_PATH="${REPO_ROOT}/17_verify_macos_crash_reporter.sh"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export STUB_BIN="${TMP_ROOT}/bin"
  export APP_PATH="${TMP_ROOT}/OutlookMailApp"
  export REPORT_DIR="${TMP_ROOT}/CrashReports"
  export MAKE_LOG="${TMP_ROOT}/make.log"
  mkdir -p "${STUB_BIN}" "${REPORT_DIR}"
}

teardown() {
  rm -rf "${TMP_ROOT}"
}

create_make_success_stub() {
  cat > "${STUB_BIN}/make" <<'EOF'
#!/bin/bash
printf "make %s\n" "$*" >> "${MAKE_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/make"
}

create_make_failure_stub() {
  cat > "${STUB_BIN}/make" <<'EOF'
#!/bin/bash
printf "make %s\n" "$*" >> "${MAKE_LOG}"
exit 1
EOF
  chmod +x "${STUB_BIN}/make"
}

create_app_success_flow_stub() {
  cat > "${APP_PATH}" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${OUTLOOK_MACOS_FORCE_CRASH_ON_LAUNCH:-0}" = "1" ]; then
  exit 86
fi
mkdir -p "${CRASH_REPORT_DIR}"
touch "${CRASH_REPORT_DIR}/crash-smoke.plcrash"
touch "${CRASH_REPORT_DIR}/crash-smoke.json"
echo "CrashReporter: saved pending crash report to ${CRASH_REPORT_DIR}/crash-smoke.plcrash"
sleep 10
EOF
  chmod +x "${APP_PATH}"
}

create_app_force_crash_bad_stub() {
  cat > "${APP_PATH}" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${APP_PATH}"
}

@test "R001: script enforces strict fail-fast mode" {
  #R001
  run rg "set -euo pipefail" "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
}

@test "R025,R030: script fails clearly when build step fails" {
  #R025 #R030
  create_make_failure_stub
  create_app_success_flow_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" MAKE_LOG="${MAKE_LOG}" APP_EXECUTABLE="${APP_PATH}" CRASH_REPORT_DIR="${REPORT_DIR}" STARTUP_WAIT_SECONDS=1 bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"failed to build app executable for crash reporter verification"* ]]
}

@test "R010: script fails when forced-crash launch exits zero" {
  #R010
  create_make_success_stub
  create_app_force_crash_bad_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" MAKE_LOG="${MAKE_LOG}" APP_EXECUTABLE="${APP_PATH}" CRASH_REPORT_DIR="${REPORT_DIR}" STARTUP_WAIT_SECONDS=1 bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"expected forced crash run to exit non-zero"* ]]
}

@test "R005,R015,R020,R025,R030,R035,R040: script verifies crash persistence via fresh artifacts and logs" {
  #R005 #R015 #R020 #R025 #R030 #R035 #R040
  create_make_success_stub
  create_app_success_flow_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" MAKE_LOG="${MAKE_LOG}" APP_EXECUTABLE="${APP_PATH}" CRASH_REPORT_DIR="${REPORT_DIR}" STARTUP_WAIT_SECONDS=2 bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"PLCrashReporter verification passed"* ]]
  [[ "${output}" == *"crash-smoke.plcrash"* ]]
  [[ "${output}" == *"crash-smoke.json"* ]]
  run rg "^make _ui-build$" "${MAKE_LOG}"
  [ "$status" -eq 0 ]
}
