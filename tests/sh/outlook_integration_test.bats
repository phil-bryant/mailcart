#!/usr/bin/env bats

load helpers/repo_root

setup() {
  #R001: Resolve repository root and integration-test source path for contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/cpp_core/tests/outlook_integration_test.cpp"
}

@test "R001: metrics harness declares constructor and recorders" {
  #R001-T01: Metrics harness declares constructor plus expectation/test recorders for aggregate counting.
  run rg -F "class TestMetrics" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "void RecordExpectation(bool passed)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "void RecordTest(bool passed)" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: metrics harness exposes aggregate getter family" {
  #R005-T01: Metrics harness exposes total/failed/passed getters for tests and expectations.
  run rg -F "int TotalTests() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "int PassedTests() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "int PassedExpectations() const" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R010: fake gateway implements deterministic search/message payload methods" {
  #R010-T01: Fake gateway class implements deterministic search and message payload methods.
  run rg -F "class FakeOutlookGateway : public OutlookServiceGateway" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "FetchSearchPayload(std::string query, int limit) const override" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "FetchMessagePayload(std::string message_id) const override" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R015: fake parser implements deterministic parse methods" {
  #R015-T01: Fake parser class implements deterministic search and message parse methods.
  run rg -F "class FakeOutlookParser : public OutlookPayloadParser" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "ParseSearchPayload(const std::string &raw_payload) const override" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "ParseMessagePayload(const std::string &raw_payload) const override" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R020: harness defines expectation and test-runner functions" {
  #R020-T01: Harness defines expectation evaluator and named test runner functions.
  run rg -F "bool Expect(const std::string &expectation_name, bool condition)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "bool RunIntegrationTest(const std::string &test_name, bool (*test_function)())" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R025: integration harness defines MIME and Mailcart robustness tests" {
  #R025-T01: Integration harness defines MIME and Mailcart robustness test functions.
  run rg -F "bool TestMimeContent()" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "bool TestMailcartRobustness()" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R030: integration harness defines Outlook population and client-mapping tests" {
  #R030-T01: Integration harness defines Outlook mailcart population and client mapping test functions.
  run rg -F "bool TestOutlookMailcartPopulation()" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "bool TestOutlookClientSearchAndRead()" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R035: main runs all checks and reports final summary" {
  #R035-T01: Main function runs all checks and reports final pass/fail summary text.
  run rg -F "int main()" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "All outlook integration checks passed." "${SRC}"
  [ "$status" -eq 0 ]
}
