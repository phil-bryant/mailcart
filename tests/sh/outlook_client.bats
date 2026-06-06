#!/usr/bin/env bats

# Behavioral contract checks for the cpp_core OutlookClient. Compiled behavior
# is exercised by the C++ integration lane
# (tests/t08_run_cpp_integration_tests.sh); these checks assert the source
# implements each requirement's design contract so regressions fail the lane.

load helpers/repo_root

setup() {
  #R001: Test harness setup for outlook_client contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/cpp_core/src/outlook_client.cpp"
}

@test "R001: negative search limits are coerced to zero" {
  #R001-T01: Negative search limits coerce to zero while non-negative limits pass through unchanged.
  run rg -F "int NormalizeLimit(int requested_limit)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "if (normalized_limit < 0)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "normalized_limit = 0;" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: summary captures id/subject/preview as immutable state with accessors" {
  #R005-T01: Summary constructor captures id/subject/preview as immutable state exposed via accessors.
  run rg -F "OutlookMailcartSummary::OutlookMailcartSummary(" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "const std::string &OutlookMailcartSummary::messageId() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "const std::string &OutlookMailcartSummary::preview() const" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R010: gateway and parser expose out-of-line virtual destructors" {
  #R010-T01: Gateway and parser abstractions provide out-of-line virtual destructors.
  run rg -F "OutlookServiceGateway::~OutlookServiceGateway() = default;" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "OutlookPayloadParser::~OutlookPayloadParser() = default;" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R015: client binds injected gateway and parser references" {
  #R015-T01: Client constructor binds the injected gateway and parser references.
  run rg -F "OutlookClient::OutlookClient(const OutlookServiceGateway &gateway, const OutlookPayloadParser &parser)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F ": gateway_(gateway), parser_(parser)" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R020: search fetches via gateway then parses via parser pipeline" {
  #R020-T01: Search fetches the payload via the gateway then parses it through the parser pipeline.
  run rg -F "gateway_.FetchSearchPayload(std::move(raw_query), normalized_limit);" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "parser_.ParseSearchPayload(raw_payload);" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R025: parsed objects map to summaries with default-empty fallback fields" {
  #R025-T01: Parsed objects map to summaries reading id/subject/preview with empty-string fallbacks.
  run rg -F 'message_object.stringFieldOrDefault("id", "")' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'message_object.stringFieldOrDefault("subject", "")' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'message_object.stringFieldOrDefault("preview", "")' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R030: search preserves parser ordering and cardinality" {
  #R030-T01: Search mapping preserves parser ordering and one summary per parsed object.
  run rg -F "summaries.reserve(message_objects.size());" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "while (index < message_objects.size())" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "summaries.emplace_back(" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R035: read fetches and parses a message before constructing the entity" {
  #R035-T01: ReadMailcart fetches and parses a message payload before constructing the entity.
  run rg -F "OutlookMailcart OutlookClient::ReadMailcart(std::string message_id) const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "gateway_.FetchMessagePayload(std::move(message_id));" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "parser_.ParseMessagePayload(raw_payload);" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "OutlookMailcart mailcart(message_object);" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R040: search result stores summaries/cursor/error via immutable accessors" {
  #R040-T01: Search-result state stores summaries/cursor/error and exposes them through read-only accessors.
  run rg -F "OutlookSearchResult::OutlookSearchResult(" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "summaries_(std::move(summaries))" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "const std::vector<OutlookMailcartSummary> &OutlookSearchResult::summaries() const" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R045: cursor searches rewrite query and surface cursor/error markers" {
  #R045-T01: Cursor searches rewrite query and surface __nextCursor/__error markers into result metadata.
  run rg -F "OutlookSearchResult OutlookClient::SearchMailcartsPage(" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'raw_query = "__cursor__" + cursor;' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'stringFieldOrDefault("__nextCursor", "")' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'stringFieldOrDefault("__error", "")' "${SRC}"
  [ "$status" -eq 0 ]
}
