# Outlook Integration Test Harness Requirements

## Scope

Applies to `cpp_core/tests/outlook_integration_test.cpp`.

R001  Statement: Accumulate test and expectation pass/fail counts through `TestMetrics`.
Design: `TestMetrics` constructor initializes counters, and `RecordExpectation` / `RecordTest` update totals and failures.
Tests:
- R001-T01: Metrics harness declares constructor plus expectation/test recorders for aggregate counting.

R005  Statement: Report aggregate metrics through read-only `TestMetrics` getters.
Design: `TotalTests`/`FailedTests`/`PassedTests` and `TotalExpectations`/`FailedExpectations`/`PassedExpectations` expose current aggregate state.
Tests:
- R005-T01: Metrics harness exposes total/failed/passed getters for tests and expectations.

R010  Statement: Provide a deterministic fake Outlook service gateway returning canned search and message payloads.
Design: `FakeOutlookGateway` implements `FetchSearchPayload` and `FetchMessagePayload` with stable string payloads.
Tests:
- R010-T01: Fake gateway class implements deterministic search and message payload methods.

R015  Statement: Provide a deterministic fake Outlook payload parser returning canned search and message objects.
Design: `FakeOutlookParser` implements `ParseSearchPayload` and `ParseMessagePayload` by returning fixed `OutlookJsonObject` fixtures.
Tests:
- R015-T01: Fake parser class implements deterministic search and message parse methods.

R020  Statement: Drive named test execution and expectation evaluation through a console harness.
Design: `Expect` records and prints expectation outcomes, and `RunIntegrationTest` executes named tests while recording pass/fail metrics.
Tests:
- R020-T01: Harness defines expectation evaluator and named test runner functions.

R025  Statement: Verify MIME detection and Mailcart normalization robustness in dedicated integration checks.
Design: `TestMimeContent` and `TestMailcartRobustness` assert MIME behavior and normalized Mailcart invariants.
Tests:
- R025-T01: Integration harness defines MIME and Mailcart robustness test functions.

R030  Statement: Verify Outlook mailcart population and Outlook client search/read mappings.
Design: `TestOutlookMailcartPopulation` and `TestOutlookClientSearchAndRead` assert mapped entity fields and client behavior.
Tests:
- R030-T01: Integration harness defines Outlook mailcart population and client mapping test functions.

R035  Statement: Aggregate all integration checks and return a final pass/fail exit status.
Design: `main` executes all integration tests, reports aggregate metrics, and returns non-zero on failure.
Tests:
- R035-T01: Main function runs all checks and reports final pass/fail summary text.

## Changelog

- 2026-06-06: Added requirements coverage for `cpp_core/tests/outlook_integration_test.cpp`.
