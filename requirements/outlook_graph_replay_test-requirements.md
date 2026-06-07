# Outlook Graph Replay Test Harness Requirements

## Scope

Applies to `cpp_core/tests/outlook_graph_replay_test.mm` and replay fixtures under
`cpp_core/tests/fixtures/graph/`.

R001  Statement: Replay harness tracks aggregate test and expectation pass/fail metrics.
Design: `ReplayMetrics`, `Expect`, and `RunReplayTest` track totals and emit per-test output.
Tests:
- R001-T01: Verify replay metrics, expectation runner, and named test runner declarations exist.

R005  Statement: Replay fixtures are loaded from deterministic checked-in JSON files.
Design: `FixturePath` resolves fixture paths from `MAILCART_REPO_ROOT` and `LoadFixture` returns UTF-8 fixture text.
Tests:
- R005-T01: Verify fixture path and fixture loader helpers exist.

R010  Statement: Replay transport/auth hooks provide deterministic Graph request behavior.
Design: `SetReplayResponses`, `ReplayTransport`, `ReplayRefresh`, and `ReplayTokenResolver` provide queue-backed responses, refresh signaling, and deterministic token transitions.
Tests:
- R010-T01: Verify queued transport, refresh hook, and token resolver replay helpers exist.

R015  Statement: Search replay covers the 401-refresh-retry branch and deterministic result mapping.
Design: `TestSearchPayloadRefreshReplay` runs `BuildGraphSearchPayload` with a queued 401 then 200 response and asserts refresh/token retry behavior.
Tests:
- R015-T01: Verify search replay test function executes queued 401->200 behavior and refresh assertions.

R020  Statement: Message replay covers deterministic message+attachment merge behavior.
Design: `TestMessagePayloadReplay` replays message and attachments responses and asserts merged attachment payload content.
Tests:
- R020-T01: Verify message replay test function asserts attachment merge and message id mapping.

R025  Statement: Error replay covers non-2xx transport diagnostics and truncation behavior.
Design: `TestFetchGraphGetDataErrorTruncation` replays a 500 response with long body text and asserts nil payload plus bounded error text.
Tests:
- R025-T01: Verify error replay test function asserts nil payload and truncated diagnostic text.

R030  Statement: Replay harness main executes all replay checks and fails fast on regressions.
Design: `main` runs all replay tests, resets Graph hooks, prints summary, and returns non-zero on failure.
Tests:
- R030-T01: Verify replay harness main executes all replay test functions and reports pass/fail summary text.

## Changelog

- 2026-06-07: Created deterministic Graph replay harness requirements for recorded fixture testing.
