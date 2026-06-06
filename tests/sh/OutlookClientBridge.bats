#!/usr/bin/env bats

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  BRIDGE_MM="${REPO_ROOT}/macos_app/Bridge/OutlookClientBridge.mm"
  BRIDGE_H="${REPO_ROOT}/macos_app/Bridge/OutlookClientBridge.h"
}

@test "R001: bridge exposes ObjC search/read entrypoints backed by C++ gateway fetch operations" {
  #R001
  run rg -F "searchMailcartsWithQuery:" "${BRIDGE_H}"
  [ "$status" -eq 0 ]
  run rg -F "readMailcartWithMessageId:" "${BRIDGE_H}"
  [ "$status" -eq 0 ]
  run rg -F "std::string FetchSearchPayload(std::string query, int limit)" "${BRIDGE_MM}"
  [ "$status" -eq 0 ]
  run rg -F "std::string FetchMessagePayload(std::string message_id)" "${BRIDGE_MM}"
  [ "$status" -eq 0 ]
}

@test "R040: bridge owns its C++ OutlookClient through a std::unique_ptr lifecycle" {
  #R040
  run rg -F "std::unique_ptr<OutlookClient> _client;" "${BRIDGE_MM}"
  [ "$status" -eq 0 ]
  run rg -F "_client = std::make_unique<OutlookClient>(_gateway, _parser);" "${BRIDGE_MM}"
  [ "$status" -eq 0 ]
}

@test "R045: bridge maps C++ results into immutable ObjC DTO arrays and objects" {
  #R045
  run rg -F "NSMutableArray<OutlookMailcartSummaryDTO *> *result" "${BRIDGE_MM}"
  [ "$status" -eq 0 ]
  run rg -F "NSArray<OutlookMailcartSummaryDTO *> *immutable_result = [result copy];" "${BRIDGE_MM}"
  [ "$status" -eq 0 ]
  run rg -F "OutlookMailcartDTO *)readMailcartWithMessageId:" "${BRIDGE_MM}"
  [ "$status" -eq 0 ]
}
