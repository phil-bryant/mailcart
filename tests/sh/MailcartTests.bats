#!/usr/bin/env bats

# Interface contract checks for the macOS Swift unit-test suite.

load helpers/repo_root

setup() {
  #R001: Test harness setup for MailcartTests contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/macos_app/Tests/MailcartTests.swift"
}

@test "R001: unit-test suite declares deterministic baseline test cases" {
  #R001-T01: MailcartTests declares launch-mode behavior XCTest cases.
  run rg -F "final class MailcartTests: XCTestCase {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "func testDetectLaunchModeUsesUITestingArgument() {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "func testDetectLaunchModeUsesUITestingEnvironment() {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "func testDetectLaunchModeDefaultsToNormal() {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "detectMailcartLaunchMode(arguments:" "${SRC}"
  [ "$status" -eq 0 ]
}
