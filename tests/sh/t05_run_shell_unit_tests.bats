#!/usr/bin/env bats

# Thin-pointer contract checks for the mailcart t05 shell-unit lane wrapper.
# The wrapper delegates to the runner golden via the shared pointer shim; these
# checks assert the pointer keeps its source/set-profile/delegate contract.

load helpers/repo_root

setup() {
  #R001: Test harness setup for t05_run_shell_unit_tests contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/tests/t05_run_shell_unit_tests.sh"
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
  #R015-T01: Verify the pointer calls delegate_golden for the shell-unit golden with "$@".
  run grep 'delegate_golden "tests/t05_run_shell_unit_tests.sh" "$@"' "${SRC}"
  [ "$status" -eq 0 ]
}
