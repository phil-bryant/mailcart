# Run Matchy Mailcart API Requirements

## Scope

Applies to `scripts/matchy_mailcart_api.py`.

R001  Statement: Require a configured Outlook Graph token for API operations.
Design: Resolve `OUTLOOK_GRAPH_TOKEN` from environment and require it before issuing Graph requests.
Tests:
- Run endpoint logic without `OUTLOOK_GRAPH_TOKEN` and verify request fails non-zero with token guidance.

R005  Statement: Accept tokens with or without a leading `Bearer ` prefix.
Design: Normalize configured token values by stripping a leading `Bearer ` segment before header construction.
Tests:
- Provide `OUTLOOK_GRAPH_TOKEN` with `Bearer ` prefix and verify downstream auth header uses only token value.

R010  Statement: Build Graph request headers for authenticated JSON operations.
Design: Include `Authorization`, `Accept`, and `Content-Type` headers for Graph GET/POST operations.
Tests:
- Inspect header construction and verify all required keys are present.

R015  Statement: Fail clearly when token configuration is missing.
Design: Raise API error with explicit `OUTLOOK_GRAPH_TOKEN is required` detail when token is blank.
Tests:
- Execute header generation with empty token and verify explicit error detail.

R020  Statement: Expose message search with optional text filtering and bounded limit.
Design: Fetch recent messages, optionally filter by query against subject/preview, and return up to requested limit.
Tests:
- Stub Graph message payload and verify query filtering and limit handling in response.

R025  Statement: Move a message to a named folder, creating folder when needed.
Design: Resolve destination folder by display name (case-insensitive), create if absent, then call Graph move API.
Tests:
- Stub folder list with no match and verify create-then-move workflow.
- Stub folder list with existing match and verify move uses existing folder ID.

## Changelog

- 2026-05-12: Added script-scoped Matchy API requirements for `scripts/matchy_mailcart_api.py`.
