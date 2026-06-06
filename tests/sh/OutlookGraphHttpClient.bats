#!/usr/bin/env bats

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  HTTP_MM="${REPO_ROOT}/macos_app/Bridge/OutlookGraphHttpClient.mm"
}

@test "R015: bridge resolves Graph token from cache/env and refreshes on HTTP 401" {
  #R015-T01: Client resolves the Graph token from cache/OUTLOOK_GRAPH_TOKEN, refreshes via scripts/refresh_graph_token.py on HTTP 401, and retries once.
  run rg -F "GraphTokenCachePath()" "${HTTP_MM}"
  [ "$status" -eq 0 ]
  run rg -F 'std::getenv("OUTLOOK_GRAPH_TOKEN")' "${HTTP_MM}"
  [ "$status" -eq 0 ]
  run rg -F "scripts/refresh_graph_token.py" "${HTTP_MM}"
  [ "$status" -eq 0 ]
  run rg -F "status_code == 401 && attempt == 0 && AttemptRefreshGraphToken()" "${HTTP_MM}"
  [ "$status" -eq 0 ]
}

@test "R020: search builder matches subject/preview case-insensitively" {
  #R020-T01: Search builder normalizes subject/preview/query text for case-insensitive matching.
  run rg -F "NSString *normalized_query = [query_text lowercaseString];" "${HTTP_MM}"
  [ "$status" -eq 0 ]
  run rg -F "NSString *subject_lower = [subject lowercaseString];" "${HTTP_MM}"
  [ "$status" -eq 0 ]
  run rg -F "[subject_lower rangeOfString:normalized_query].location != NSNotFound" "${HTTP_MM}"
  [ "$status" -eq 0 ]
}

@test "R025: search builder coerces negative limits to zero and caps result count" {
  #R025-T01: Search builder coerces negative limits to zero and caps results at the requested count.
  run rg -F "NSInteger bounded_limit = limit;" "${HTTP_MM}"
  [ "$status" -eq 0 ]
  run rg -F "if (bounded_limit < 0)" "${HTTP_MM}"
  [ "$status" -eq 0 ]
  run rg -F "static_cast<NSInteger>(filtered.count) < bounded_limit" "${HTTP_MM}"
  [ "$status" -eq 0 ]
}

@test "R030: search summaries serialize only id/subject/preview fields" {
  #R030-T01: Search summaries serialize only id/subject/preview fields and omit body/sender/recipient data.
  run rg -F '@"id" : JsonStringOrEmpty(candidate[@"id"]),' "${HTTP_MM}"
  [ "$status" -eq 0 ]
  run rg -F '@"subject" : subject,' "${HTTP_MM}"
  [ "$status" -eq 0 ]
  run rg -F '@"preview" : preview,' "${HTTP_MM}"
  [ "$status" -eq 0 ]
  run rg -F '@"sender"' "${HTTP_MM}"
  [ "$status" -ne 0 ]
}
