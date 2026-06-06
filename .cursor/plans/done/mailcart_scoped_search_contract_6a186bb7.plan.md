---
name: mailcart scoped search contract
overview: Implement strict scoped-token search for `GET /v1/messages/search` with full-body matching, AND semantics, inclusive date bounds, and normalization; add acceptance coverage and CI wiring so Mailcart CI enforces the contract.
todos:
  - id: parser-strict-scoped
    content: Implement strict scoped-token parser with 400 on invalid/unprefixed tokens and date format validation
    status: completed
  - id: normalize-and-match
    content: Add normalization and field-specific matching (subject/sender/full-body) with AND semantics and inclusive dates
    status: completed
  - id: graph-full-body
    content: "Retrieve and normalize full message body content for body: token matching"
    status: completed
  - id: acceptance-tests
    content: Add Python acceptance tests for all seven scenarios plus strict-invalid-token behavior
    status: completed
  - id: ci-wireup
    content: Wire Python acceptance tests into Mailcart CI Makefile path and update traceability references
    status: completed
  - id: docs-update
    content: Update API requirements doc to reflect new scoped search contract and behavior
    status: completed
isProject: false
---

# Implement Scoped Search Contract for Mailcart API

## Scope and Decisions
- Endpoint: `GET /v1/messages/search?query=...&limit=...` in [`/Users/phil/local/src/mailcart/scripts/matchy_mailcart_api.py`](/Users/phil/local/src/mailcart/scripts/matchy_mailcart_api.py).
- Supported tokens: `subject:`, `sender:`, `body:`, `from:`, `to:`.
- Parsing mode: **strict** — any unsupported/unprefixed token returns HTTP 400.
- `body:` behavior: search against **full message body content** (not only `bodyPreview`).
- Combination rule: all tokens combine with logical AND.

## Implementation Plan
1. Extend search query parsing in [`/Users/phil/local/src/mailcart/scripts/matchy_mailcart_api.py`](/Users/phil/local/src/mailcart/scripts/matchy_mailcart_api.py):
   - Add a deterministic tokenizer/parser for scoped tokens.
   - Validate date token formats (`YYYY-MM-DD`) and fail fast with 400 for invalid/unsupported tokens.
   - Ensure token order does not affect parsed criteria.

2. Add normalization and matching helpers in the same module:
   - Text normalization: case-fold + trim + collapse internal whitespace.
   - Apply normalization consistently to query token values and message fields.
   - Implement field-scoped match functions for subject/sender/full-body.

3. Update Graph data retrieval shape for full-body support:
   - Include body content field(s) required to evaluate `body:` accurately.
   - Convert body HTML/content to searchable plain text as needed before normalization.

4. Implement filter evaluation pipeline:
   - Apply inclusive lower/upper date bounds on `receivedDateTime` for `from:` / `to:`.
   - Enforce AND semantics across text and date dimensions.
   - Preserve `limit` behavior after filtering and keep existing auth/error handling expectations.

5. Update requirements documentation to reflect the new contract:
   - Revise [`/Users/phil/local/src/mailcart/requirements/matchy_mailcart_api-requirements.md`](/Users/phil/local/src/mailcart/requirements/matchy_mailcart_api-requirements.md) to capture strict scoped parsing, normalization, date bounds, and AND semantics.

6. Add acceptance tests in [`/Users/phil/local/src/mailcart/tests/python/test_matchy_mailcart_api.py`](/Users/phil/local/src/mailcart/tests/python/test_matchy_mailcart_api.py):
   - Field scoping correctness (`subject:`, `sender:`, `body:`).
   - Case-insensitive matching across casing variants.
   - Whitespace normalization for subject/sender/body tokens.
   - AND semantics across multiple scoped text tokens.
   - Inclusive date bounds with boundary-day fixtures.
   - Mixed text + date AND behavior.
   - Stable token parsing regardless of token order.
   - Strict 400 behavior for unsupported/unprefixed tokens.

7. Ensure CI executes these tests:
   - Wire Python test execution into [`/Users/phil/local/src/mailcart/Makefile`](/Users/phil/local/src/mailcart/Makefile) `test` flow (or equivalent CI-targeted test target).
   - Align traceability references if needed (e.g., Python test path naming expectations).

## Verification
- Run Mailcart test targets so new acceptance tests pass in CI path.
- Perform an API-level local check against running Mailcart:
  - scoped field queries return expected isolated hits,
  - mixed case/whitespace variants match consistently,
  - date boundaries are inclusive,
  - invalid tokens return 400.
- Teller integration check (external repo/system): execute Teller’s real integration test against Mailcart search endpoint using scoped and normalization-sensitive queries to confirm end-to-end contract behavior.
