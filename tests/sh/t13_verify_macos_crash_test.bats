#!/usr/bin/env bats

# Contract checks for the mailcart-owned t13 macOS crash verification lane.
# The lane is self-contained (no shim): it sets strict mode, loads the runbook
# environment and build lock, then builds and runs PLCrashReporter verification.

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/tests/t13_verify_macos_crash_test.sh"
}

@test "runs with a secure umask and strict shell mode" {
  #R001-T01: Verify the lane sets a secure umask before running.
  run grep "umask 007" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "loads the mailcart runbook environment" {
  #R005-T01: Verify the lane sources runner/config/runbook/mailcart.env.
  run grep "config/runbook/mailcart.env" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "runs the crash verification target" {
  #R010-T01: Verify the lane runs the crash verification target via make crash.
  run grep "make crash" "${SRC}"
  [ "$status" -eq 0 ]
}
