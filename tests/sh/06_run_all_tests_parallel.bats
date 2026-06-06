#!/usr/bin/env bats

src() {
  printf '%s' "${BATS_TEST_DIRNAME}/../../06_run_all_tests_parallel.sh"
}

@test "centralizes umask/strict mode via the shared pointer shim" {
  #R001-T01: Verify the pointer sources pointer_shim.sh.
  run grep "pointer_shim.sh" "$(src)"
  [ "$status" -eq 0 ]
}

@test "resolves the shim from the runner src/scripts tree" {
  #R005-T01: Verify the pointer locates the shim under runner/src/scripts.
  run grep "runner/src/scripts" "$(src)"
  [ "$status" -eq 0 ]
}

@test "selects its runbook profile explicitly before delegation" {
  #R010-T01: Verify the pointer sets RUNBOOK_PROFILE to the repo profile.
  run grep 'RUNBOOK_PROFILE="mailcart"' "$(src)"
  [ "$status" -eq 0 ]
}

@test "delegates to the mapped runner golden" {
  #R015-T01: Verify the pointer calls delegate_golden with 07_run_all_tests_parallel.sh and "$@".
  run grep 'delegate_golden "07_run_all_tests_parallel.sh" "$@"' "$(src)"
  [ "$status" -eq 0 ]
}
