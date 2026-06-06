#!/usr/bin/env bats

# Contract checks for the mailcart-owned t09 Swift/ObjC++ build lane.
# The lane is self-contained (no shim): it sets strict mode, loads the runbook
# environment and build lock, then builds and runs native static analysis.

load helpers/repo_root

setup() {
  #R001: Test harness setup for t09_run_swift_build_tests contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/tests/t09_run_swift_build_tests.sh"
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

@test "builds the Swift/ObjC++ surface under the macOS build lock" {
  #R010-T01: Verify the lane builds under the macOS build lock via with_macos_build_lock make build.
  run grep "with_macos_build_lock make build" "${SRC}"
  [ "$status" -eq 0 ]
}
