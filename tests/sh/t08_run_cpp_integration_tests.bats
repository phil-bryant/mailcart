#!/usr/bin/env bats

# Contract checks for the mailcart-owned t08 C++ integration lane.
# The lane is self-contained (no shim): it sets strict mode, loads the runbook
# environment, and runs the Makefile C++ integration target.

load helpers/repo_root

setup() {
  #R001: Test harness setup for t08_run_cpp_integration_tests contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/tests/t08_run_cpp_integration_tests.sh"
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

@test "runs the Makefile C++ integration target" {
  #R010-T01: Verify the lane runs make _cpp-test.
  run grep "make _cpp-test" "${SRC}"
  [ "$status" -eq 0 ]
}
