---
name: Fix Message 401 Handling
overview: Stabilize single-message fetch auth handling so expired/invalid tokens recover reliably and real auth failures are reported clearly without masking other conditions.
todos:
  - id: audit-message-auth-flow
    content: Review and tighten 401 retry/refresh logic in matchy_mailcart_api graph request path
    status: completed
  - id: encode-message-id-path-segment
    content: Apply safe message ID path-segment encoding before Graph single-message calls
    status: completed
  - id: add-auth-regression-tests
    content: Add tests for 401 refresh success/failure and encoded message ID behavior
    status: completed
  - id: run-targeted-python-tests
    content: Run targeted tests for message endpoint status mapping and auth handling
    status: completed
isProject: false
---

# Fix 401 Unauthorized on Message Fetch

## Scope
- Focus on the single-message endpoint: [`/Users/phil/local/src/mailcart/scripts/matchy_mailcart_api.py`](/Users/phil/local/src/mailcart/scripts/matchy_mailcart_api.py) for `GET /v1/messages/{message_id}`.
- Adjust token-refresh behavior in [`/Users/phil/local/src/mailcart/scripts/graph_token.py`](/Users/phil/local/src/mailcart/scripts/graph_token.py) only where needed to make retry behavior deterministic.
- Add/extend tests in [`/Users/phil/local/src/mailcart/tests/python/test_matchy_mailcart_api.py`](/Users/phil/local/src/mailcart/tests/python/test_matchy_mailcart_api.py).

## Plan
- Harden 401 recovery in `_graph_request()`:
  - Keep a single retry on first `401`, but make failure classification explicit (refresh-failed vs still-unauthorized).
  - Preserve clear `502` diagnostics for true upstream auth failures while preventing ambiguous generic error text.
- Normalize message-id handling before Graph call:
  - Safely URL-encode the path segment for `/me/messages/{id}` to avoid edge-case auth/lookup failures from raw path interpolation.
  - Keep query param behavior unchanged.
- Improve auth observability:
  - Return concise, structured error detail strings (status + category) so logs distinguish token-refresh failure from upstream denial.
- Add regression tests:
  - `401 -> refresh success -> 200` path.
  - `401 -> refresh failure -> 502` path with expected detail.
  - `401 -> refresh success -> second 401 -> 502` path.
  - Message IDs containing encoded padding (`%3D%3D`) and raw `==` still build valid Graph request URLs.

## Validation
- Run Python tests covering message endpoint behavior in [`/Users/phil/local/src/mailcart/tests/python/test_matchy_mailcart_api.py`](/Users/phil/local/src/mailcart/tests/python/test_matchy_mailcart_api.py).
- Confirm endpoint behavior matrix:
  - valid token + valid ID => `200`
  - stale token recoverable => `200`
  - unrecoverable auth => `502` with explicit auth detail
  - true not-found => `404` unchanged