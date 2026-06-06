#!/usr/bin/env bats

load helpers/repo_root

setup() {
  #R001: Crash-verify harness setup for script contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  export REPO_ROOT
  export SCRIPT_PATH="${REPO_ROOT}/scripts/verify_macos_crash_reporter.sh"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export STUB_BIN="${TMP_ROOT}/bin"
  export APP_PATH="${TMP_ROOT}/OutlookMailApp"
  export REPORT_DIR="${TMP_ROOT}/CrashReports"
  export MAKE_LOG="${TMP_ROOT}/make.log"
  mkdir -p "${STUB_BIN}" "${REPORT_DIR}"
}

teardown() {
  #R001: Crash-verify harness teardown for script contract checks.
  rm -rf "${TMP_ROOT}"
}

create_make_success_stub() {
  #R001: Crash-verify harness helper for a successful make stub.
  cat > "${STUB_BIN}/make" <<'EOF'
#!/bin/bash
printf "make %s\n" "$*" >> "${MAKE_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/make"
}

create_make_failure_stub() {
  #R001: Crash-verify harness helper for a failing make stub.
  cat > "${STUB_BIN}/make" <<'EOF'
#!/bin/bash
printf "make %s\n" "$*" >> "${MAKE_LOG}"
exit 1
EOF
  chmod +x "${STUB_BIN}/make"
}

create_app_success_flow_stub() {
  #R001: Crash-verify harness helper for successful app launch/crash flow stubs.
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
  #R001: Crash-verify harness helper for a bad forced-crash behavior stub.
  cat > "${APP_PATH}" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${APP_PATH}"
}

@test "R001: script enforces strict fail-fast mode" {
  #R001-T01: Script declares strict fail-fast mode (set -euo pipefail).
  run rg "set -euo pipefail" "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
}

@test "R025,R030: script fails clearly when build step fails" {
  #R025-T01: Script runs make _ui-build and fails with guidance when the build step fails.
  #R030-T01: Script fails clearly when required tooling or the app executable is unavailable.
  create_make_failure_stub
  create_app_success_flow_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" MAKE_LOG="${MAKE_LOG}" APP_EXECUTABLE="${APP_PATH}" CRASH_REPORT_DIR="${REPORT_DIR}" STARTUP_WAIT_SECONDS=1 bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"failed to build app executable for crash reporter verification"* ]]
}

@test "R010: script fails when forced-crash launch exits zero" {
  #R010-T01: Script fails when the forced-crash launch exits zero.
  create_make_success_stub
  create_app_force_crash_bad_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" MAKE_LOG="${MAKE_LOG}" APP_EXECUTABLE="${APP_PATH}" CRASH_REPORT_DIR="${REPORT_DIR}" STARTUP_WAIT_SECONDS=1 bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"expected forced crash run to exit non-zero"* ]]
}

@test "R005,R015,R020,R025,R030,R035,R040: script verifies crash persistence via fresh artifacts and logs" {
  #R005-T01: Script runs repository-relative commands from repo root regardless of caller directory.
  #R015-T01: Script marks crash persistence observed from logs or fresh artifacts.
  #R020-T01: Script requires fresh .plcrash and .json artifacts newer than the run marker.
  #R025-T01: Script runs make _ui-build and fails with guidance when the build step fails.
  #R030-T01: Script fails clearly when required tooling or the app executable is unavailable.
  #R035-T01: Successful verification prints a success banner with persisted artifact paths.
  #R040-T01: Script honors APP_EXECUTABLE, CRASH_REPORT_DIR, and STARTUP_WAIT_SECONDS overrides.
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

@test "R600: refresh_latest_artifacts resolves newest .plcrash/.json" {
  #R600-T01: refresh_latest_artifacts selects the newest artifact of each kind.
  run rg -F "refresh_latest_artifacts() {" "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  run rg -F 'local plcrash_files=("$CRASH_REPORT_DIR"/*.plcrash)' "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  run rg -F 'if [[ "$candidate" -nt "$latest_plcrash" ]]; then' "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
}

@test "R605: artifacts_are_fresh requires both artifacts newer than marker" {
  #R605-T01: artifacts_are_fresh checks both artifacts exist and are newer than MARKER_FILE.
  run rg -F "artifacts_are_fresh() {" "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  run rg -F '"$latest_plcrash" -nt "$MARKER_FILE" && "$latest_json" -nt "$MARKER_FILE"' "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
}
