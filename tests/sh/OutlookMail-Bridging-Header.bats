#!/usr/bin/env bats

# Interface contract check for the Swift bridging header. Asserts the header
# exposes the Objective-C++ Outlook client bridge interface to the Swift target.

load helpers/repo_root

setup() {
  #R001: Test harness setup for OutlookMail-Bridging-Header contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  HDR="${REPO_ROOT}/macos_app/OutlookMail-Bridging-Header.h"
}

@test "R001: bridging header imports the Outlook client bridge interface for Swift" {
  #R001-T01: The bridging header imports Bridge/OutlookClientBridge.h to expose the bridge interface to Swift.
  run rg -F '#import "Bridge/OutlookClientBridge.h"' "${HDR}"
  [ "$status" -eq 0 ]
}
