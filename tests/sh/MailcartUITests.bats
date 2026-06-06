#!/usr/bin/env bats

# Interface contract checks for the macOS end-to-end mailbox regression suite.

load helpers/repo_root

setup() {
  #R001: Test harness setup for MailcartUITests contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/macos_app/UITests/MailcartUITests.swift"
}

@test "R001: regression suite launches the fixture app and declares the core cases" {
  #R001-T01: MailcartUITests launches the fixture app and declares the search/pagination/detail regression cases.
  run rg -F "final class MailcartUITests: XCTestCase {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'app.launchArguments += ["--ui-testing"]' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "func testSearchFilterFindsFixtureRow() {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "func testLoadMoreAppendsFixtureRows() {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "func testSelectingSummaryLoadsFixtureDetail() {" "${SRC}"
  [ "$status" -eq 0 ]
}
