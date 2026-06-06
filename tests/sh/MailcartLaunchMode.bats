#!/usr/bin/env bats

# Interface contract checks for launch-mode detection helpers.

load helpers/repo_root

setup() {
  #R001: Test harness setup for MailcartLaunchMode contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/macos_app/UI/MailcartLaunchMode.swift"
}

@test "R001: launch-mode helper inspects args/env and exposes ProcessInfo wrapper" {
  #R001-T01: launch-mode helper inspects args/env and exposes a ProcessInfo wrapper.
  run rg -F "func detectMailcartLaunchMode(arguments: [String], environment: [String: String]) -> MailcartAppLaunchMode {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'arguments.contains("--ui-testing")' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'environment["MAILCART_UI_TEST_MODE"] == "1"' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "func detectMailcartLaunchMode(processInfo: ProcessInfo = .processInfo) -> MailcartAppLaunchMode {" "${SRC}"
  [ "$status" -eq 0 ]
}
