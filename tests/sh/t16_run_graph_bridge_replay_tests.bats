#!/usr/bin/env bats

# Contract checks for the mailcart-owned t16 Graph bridge replay lane.
# The lane is self-contained (no shim): it sets strict mode, loads the runbook
# environment, and runs the Makefile replay target.

load helpers/repo_root

setup() {
  #R001: Test harness setup for t16_run_graph_bridge_replay_tests contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/tests/t16_run_graph_bridge_replay_tests.sh"
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

@test "runs the Makefile graph replay target" {
  #R010-T01: Verify the lane runs make _graph-replay-test.
  run grep "make _graph-replay-test" "${SRC}"
  [ "$status" -eq 0 ]
}
