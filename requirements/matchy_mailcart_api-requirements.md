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

R020  Statement: Expose strict scoped message search with field filters, inclusive date bounds, normalization, AND semantics, bounded limit, and stable retrieval for older date windows.
Design: `GET /v1/messages/search?query=...&limit=...` accepts only scoped tokens (`subject:`, `sender:`, `body:`, `from:`, `to:`). Text matching is case-insensitive and normalizes trim + collapsed whitespace. `body:` matches full message body content (including HTML converted to text). Multiple tokens combine with logical AND. Date filters are inclusive by received date, and unsupported/unscoped tokens return HTTP 400. When `from:` and/or `to:` are present, the Graph request includes a server-side `receivedDateTime` `$filter` and the API follows `@odata.nextLink` pages (bounded scan budget) so messages outside the first Graph page still participate in filtering. Text-only scoped queries keep single-page behavior to avoid unnecessary latency.
Tests:
- Verify field scoping correctness (`subject:doordash`, `sender:doordash`, `body:doordash`) returns only the expected seeded message per field.
- Verify case-insensitive behavior returns identical results for mixed-case query variants.
- Verify whitespace-normalized query values match canonical message values in subject/sender/body.
- Verify AND semantics across multiple scoped tokens returns only messages satisfying every token.
- Verify inclusive `from:`/`to:` date bounds include boundary-day messages and exclude out-of-range messages.
- Verify Graph search params include `receivedDateTime` `$filter` clauses for scoped `from:`/`to:` windows.
- Verify combined text + date filters apply AND semantics across text/date dimensions.
- Verify date-scoped searches follow `@odata.nextLink` pagination and return in-window matches from later pages.
- Verify token order does not change results for equivalent scoped-token sets.
- Verify unsupported/unscoped token content returns HTTP 400.

R025  Statement: Move a message to a named folder, creating folder when needed.
Design: Resolve destination folder by display name (case-insensitive), create if absent, then call Graph move API.
Tests:
- Stub folder list with no match and verify create-then-move workflow.
- Stub folder list with existing match and verify move uses existing folder ID.

R026  Statement: Refresh expired Graph access tokens using a stored refresh token.
Design: Resolve refresh credentials from 1Password and `OUTLOOK_GRAPH_CLIENT_ID`, call Microsoft token endpoint, and persist refreshed tokens to the shared cache file.
Tests:
- Mock token endpoint success and verify cache file receives updated access and refresh tokens.

R027  Statement: Retry Graph requests once after a 401 authentication failure.
Design: Invalidate in-memory token state, force refresh, and retry the original Graph request before surfacing an error.
Tests:
- Mock Graph 401 followed by refresh success and verify the retried request succeeds.

R028  Statement: Persist refreshed OAuth session data to a shared local cache file.
Design: Write access token, refresh token, expiry, and client id to `~/.cache/mailcart/graph_oauth.json` with restrictive permissions.
Tests:
- Refresh token flow and verify cache file contents and mode.

R029  Statement: Expose token health metadata from the API health endpoint.
Design: `/health` returns `token_status` and `token_expires_at` when token state can be resolved.
Tests:
- Stub valid cached token and verify health payload includes token metadata.

R030  Statement: Surface Graph auth failures instead of empty search results.
Design: When fallback message fetch fails due to authentication, return explicit 502 auth detail rather than `{"messages": []}`.
Tests:
- Mock auth failures on search and fallback fetch and verify API returns auth error detail.

R035  Statement: Expose a single-message fetch endpoint with body, recipients, and metadata for downstream UIs.
Design: `GET /v1/messages/{message_id}` calls Microsoft Graph `/me/messages/{id}?$select=id,subject,bodyPreview,body,from,toRecipients,receivedDateTime` and returns `{message_id, subject, preview, received_at, sender, recipients, html_body, text_body, body_text}`. The endpoint distinguishes HTML vs plain text body (`html_body` vs `text_body`); `recipients` is a comma-separated list of `toRecipients` addresses. Blank `message_id` returns HTTP 400.
Tests:
- R035-T01: Mock Graph response with HTML and plain-text bodies and verify field mapping and route registration.
- R035-T02: Pass a blank message id and verify HTTP 400 is raised.

R040  Statement: Start the Matchy Mailcart API over HTTPS only.
Design: API startup resolves TLS cert/key file paths from `MAILCART_MATCHY_TLS_CERT_FILE` and `MAILCART_MATCHY_TLS_KEY_FILE` (with localhost defaults under `~/.mailcart`) and launches uvicorn with `ssl_certfile` and `ssl_keyfile`.
Tests:
- Mock startup dependencies and verify uvicorn receives SSL cert/key parameters.
- Verify reuse health probes target `https://127.0.0.1:8788/health`.

R045  Statement: Fail fast when required API TLS materials are missing.
Design: Startup exits non-zero with explicit guidance when either configured TLS cert or key file does not exist.
Tests:
- Run startup with missing `MAILCART_MATCHY_TLS_CERT_FILE` and verify explicit failure message.
- Run startup with missing `MAILCART_MATCHY_TLS_KEY_FILE` and verify explicit failure message.

## Changelog

- 2026-05-12: Added script-scoped Matchy API requirements for `scripts/matchy_mailcart_api.py`.
- 2026-05-19: Added OAuth refresh, retry-on-401, cache persistence, health token status, and auth error surfacing requirements.
- 2026-05-19: Added R035 single-message fetch endpoint for downstream UIs (Teller Match Review three-pane view).
- 2026-05-27: Added HTTPS-only startup (R040) and fail-fast TLS material validation (R045) for Matchy Mailcart API.
- 2026-05-28: Updated R020 to strict scoped-token search contract with full-body matching, normalization, inclusive dates, AND semantics, and 400 on unsupported/unscoped tokens.
- 2026-05-29: Updated R020 to require server-side Graph date filters and bounded pagination for date-scoped queries so older-window inbox matches are discoverable beyond the first Graph page.
