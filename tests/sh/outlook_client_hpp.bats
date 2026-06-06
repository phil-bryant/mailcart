#!/usr/bin/env bats

# Interface contract checks for the cpp_core OutlookClient header. The compiled
# behavior is exercised by the C++ integration lane; these checks assert the
# header declares the interface each requirement depends on.

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  HDR="${REPO_ROOT}/cpp_core/include/outlook_client.hpp"
}

@test "R001: header declares summary/result types, gateway/parser abstractions, and client operations" {
  #R001-T01: Verify the header declares the summary/search-result types, gateway/parser abstractions, and client operations.
  run rg -F "OutlookMailcartSummary(std::string message_id, std::string subject, std::string preview, std::string received_at);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "OutlookSearchResult(std::vector<OutlookMailcartSummary> summaries, std::string next_cursor, std::string error_message);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "virtual ~OutlookServiceGateway();" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] virtual std::string FetchSearchPayload(std::string query, int limit) const = 0;" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "virtual ~OutlookPayloadParser();" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "OutlookClient(const OutlookServiceGateway &gateway, const OutlookPayloadParser &parser);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] OutlookMailcart ReadMailcart(std::string message_id) const;" "${HDR}"
  [ "$status" -eq 0 ]
}
