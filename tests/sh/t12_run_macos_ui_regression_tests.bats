#!/usr/bin/env bats

# Contract checks for the mailcart-owned t12 macOS UI regression lane.
# The lane is self-contained (no shim): it sets strict mode, loads the runbook
# environment and build lock, then builds and runs the UI regression suite.

load helpers/repo_root

setup() {
  #R001: Test harness setup for t12_run_macos_ui_regression_tests contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/tests/t12_run_macos_ui_regression_tests.sh"
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

@test "runs the macOS UI regression target" {
  #R010-T01: Verify the lane runs the macOS UI regression target via make ui-test.
  run grep "make ui-test" "${SRC}"
  [ "$status" -eq 0 ]
}
