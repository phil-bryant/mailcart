#!/usr/bin/env bats

load helpers/repo_root

setup() {
  #R001: Resolve source and fixture roots for replay harness contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/cpp_core/tests/outlook_graph_replay_test.mm"
  FIXTURE_ROOT="${REPO_ROOT}/cpp_core/tests/fixtures/graph"
}

@test "R001: replay metrics and runners are declared" {
  #R001-T01: Verify replay metrics, expectation runner, and named test runner declarations exist.
  run rg -F "class ReplayMetrics" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "bool Expect(const std::string &name, bool passed)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "bool RunReplayTest(const std::string &test_name, bool (*test_function)())" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: replay harness has fixture path and loader helpers" {
  #R005-T01: Verify fixture path and fixture loader helpers exist.
  run rg -F "NSString *FixturePath(const std::string &fixture_name)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "std::string LoadFixture(const std::string &fixture_name)" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R010: replay transport/auth helpers are declared" {
  #R010-T01: Verify queued transport, refresh hook, and token resolver replay helpers exist.
  run rg -F "void SetReplayResponses(const std::vector<ReplayResponse> &responses)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "NSData *ReplayTransport(NSURLRequest *request, NSHTTPURLResponse **http_response, NSError **request_error)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "BOOL ReplayRefresh()" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "NSString *ReplayTokenResolver()" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R015: search replay covers 401-refresh-retry assertions" {
  #R015-T01: Verify search replay test function executes queued 401->200 behavior and refresh assertions.
  run rg -F "bool TestSearchPayloadRefreshReplay()" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "search replay called refresh branch" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R020: message replay covers attachment merge assertions" {
  #R020-T01: Verify message replay test function asserts attachment merge and message id mapping.
  run rg -F "bool TestMessagePayloadReplay()" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "message replay merges one attachment" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R025: error replay covers truncation assertions" {
  #R025-T01: Verify error replay test function asserts nil payload and truncated diagnostic text.
  run rg -F "bool TestFetchGraphGetDataErrorTruncation()" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "error replay body text is truncated" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R030: replay main runs all replay tests and reports summary" {
  #R030-T01: Verify replay harness main executes all replay test functions and reports pass/fail summary text.
  run rg -F "int main()" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "All outlook graph replay checks passed." "${SRC}"
  [ "$status" -eq 0 ]
}

@test "fixtures: graph replay fixtures are present" {
  #R005-T01: Verify recorded search/message/attachments and 401 fixtures exist on disk.
  [ -f "${FIXTURE_ROOT}/search_response.json" ]
  [ -f "${FIXTURE_ROOT}/message_response.json" ]
  [ -f "${FIXTURE_ROOT}/attachments_response.json" ]
  [ -f "${FIXTURE_ROOT}/error_401.json" ]
}
