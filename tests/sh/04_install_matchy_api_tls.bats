#!/usr/bin/env bats

src() {
  printf '%s' "${BATS_TEST_DIRNAME}/../../04_install_matchy_api_tls.sh"
}

@test "centralizes umask/strict mode via the shared pointer shim" {
  #R001-T01
  run grep "pointer_shim.sh" "$(src)"
  [ "$status" -eq 0 ]
}

@test "resolves the shim from the runner src/scripts tree" {
  #R005-T01
  run grep "runner/src/scripts" "$(src)"
  [ "$status" -eq 0 ]
}

@test "selects its runbook profile explicitly before delegation" {
  #R010-T01
  run grep 'RUNBOOK_PROFILE="mailcart"' "$(src)"
  [ "$status" -eq 0 ]
}

@test "delegates to the mapped runner golden" {
  #R015-T01
  run grep 'delegate_golden "src/scripts/install_api_tls_generic.sh" "$@"' "$(src)"
  [ "$status" -eq 0 ]
}
