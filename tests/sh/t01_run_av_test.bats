#!/usr/bin/env bats

# Thin-pointer contract checks for the mailcart t01 anti-virus lane wrapper.
# The wrapper delegates to the runner golden via the shared pointer shim; these
# checks assert the pointer keeps its source/set-profile/delegate contract.

load helpers/repo_root

setup() {
  #R001: Test harness setup for t01_run_av_test contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/tests/t01_run_av_test.sh"
}

@test "centralizes umask/strict mode via the shared pointer shim" {
  #R001-T01: Verify the pointer sources pointer_shim.sh.
  run grep "pointer_shim.sh" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "resolves the shim from the runner src/scripts tree" {
  #R005-T01: Verify the pointer locates the shim under runner/src/scripts.
  run grep "runner/src/scripts" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "selects its runbook profile explicitly before delegation" {
  #R010-T01: Verify the pointer sets RUNBOOK_PROFILE to the repo profile.
  run grep 'RUNBOOK_PROFILE="mailcart"' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "delegates to the mapped runner golden" {
  #R015-T01: Verify the pointer calls delegate_golden for the anti-virus golden with "$@".
  run grep 'delegate_golden "tests/t01_run_av_test.sh" "$@"' "${SRC}"
  [ "$status" -eq 0 ]
}
