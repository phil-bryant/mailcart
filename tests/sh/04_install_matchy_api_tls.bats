#!/usr/bin/env bats

src() {
  printf '%s' "${BATS_TEST_DIRNAME}/../../04_install_matchy_api_tls.sh"
}

@test "enables secure umask and strict shell mode" {
  #R001-T01
  run grep "umask 007" "$(src)"
  [ "$status" -eq 0 ]
  run grep "set -euo pipefail" "$(src)"
  [ "$status" -eq 0 ]
}

@test "derives script and runner paths from script location" {
  #R005-T01
  run grep "SCRIPT_DIR=" "$(src)"
  [ "$status" -eq 0 ]
  run grep "RUNNER_HOME=" "$(src)"
  [ "$status" -eq 0 ]
  run grep "runner" "$(src)"
  [ "$status" -eq 0 ]
}

@test "loads mailcart runbook profile before delegation" {
  #R010-T01
  run grep "export RUNBOOK_REPO_ROOT" "$(src)"
  [ "$status" -eq 0 ]
  run grep "config/runbook/mailcart.env" "$(src)"
  [ "$status" -eq 0 ]
}

@test "delegates to mapped runner TLS installer golden" {
  #R015-T01
  run grep "exec \"\${RUNNER_HOME}/05_install_matchy_api_tls.sh\" \"\$@\"" "$(src)"
  [ "$status" -eq 0 ]
}
