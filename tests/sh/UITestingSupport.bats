#!/usr/bin/env bats

# Interface contract checks for the macOS UI-testing support bridge.

load helpers/repo_root

setup() {
  #R001: Test harness setup for UITestingSupport contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/macos_app/UI/UITestingSupport.swift"
  MODE_SRC="${REPO_ROOT}/macos_app/UI/MailcartLaunchMode.swift"
}

@test "R001: launch mode detection routes UI-test launches to the fixture bridge" {
  #R001-T01: Launch mode detection and bridge factory route UI-test launches to the fixture bridge.
  run rg -F "func detectMailcartLaunchMode(arguments: [String], environment: [String: String]) -> MailcartAppLaunchMode {" "${MODE_SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'arguments.contains("--ui-testing")' "${MODE_SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'environment["MAILCART_UI_TEST_MODE"] == "1"' "${MODE_SRC}"
  [ "$status" -eq 0 ]
  run rg -F "return UITestingFixtureBridge(processInfo: processInfo)" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: fixture bridge returns cursor-paged in-memory summaries" {
  #R005-T01: UITestingFixtureBridge searches in-memory fixtures and returns cursor-paged summaries.
  run rg -F "final class UITestingFixtureBridge: NSObject, OutlookBridgeClient, @unchecked Sendable {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "func searchMailcarts(withQuery query: String, limit: Int, cursor: String) -> OutlookSearchResultDTO {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "let nextCursor = upperBound < filtered.count ? String(upperBound) : \"\"" "${SRC}"
  [ "$status" -eq 0 ]
}
