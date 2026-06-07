#!/usr/bin/env bats

load helpers/repo_root

setup() {
  #R005: Test harness setup for OutlookBridgeModels contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  MODELS_H="${REPO_ROOT}/macos_app/Bridge/OutlookBridgeModels.h"
  MODELS_M="${REPO_ROOT}/macos_app/Bridge/OutlookBridgeModels.m"
}

@test "R005: bridge DTO models are immutable copies with init disallowed" {
  #R005-T01: DTO models declare immutable copied properties through designated initializers with init made unavailable.
  run rg -F "@interface OutlookMailcartSummaryDTO : NSObject" "${MODELS_H}"
  [ "$status" -eq 0 ]
  run rg -F "@interface OutlookMailcartDTO : NSObject" "${MODELS_H}"
  [ "$status" -eq 0 ]
  run rg -F "nonatomic, copy, readonly) NSString *messageId" "${MODELS_H}"
  [ "$status" -eq 0 ]
  run rg -c -F -- "- (instancetype)init NS_UNAVAILABLE;" "${MODELS_H}"
  [ "$status" -eq 0 ]
  [ "${output}" -ge 2 ]
  run rg -F "// #R005: Materialize immutable search-result DTO values through the designated initializer." "${MODELS_M}"
  [ "$status" -eq 0 ]
  run rg -F "// #R005: Materialize immutable attachment DTO values through the designated initializer." "${MODELS_M}"
  [ "$status" -eq 0 ]
}
