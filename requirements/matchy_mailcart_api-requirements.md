# Run Matchy Mailcart API Requirements

## Scope

Applies to `scripts/matchy_mailcart_api.py`.

R001  Statement: Require a configured Outlook Graph token for API operations.
Design: Resolve `OUTLOOK_GRAPH_TOKEN` from environment and require it before issuing Graph requests.
Tests:
- R001-T01: API operations resolve a Graph access token before issuing requests.

R005  Statement: Accept tokens with or without a leading `Bearer ` prefix.
Design: Normalize configured token values by stripping a leading `Bearer ` segment before header construction.
Tests:
- R005-T01: Configured tokens are normalized by stripping a leading `Bearer ` prefix.

R010  Statement: Build Graph request headers for authenticated JSON operations.
Design: Include `Authorization`, `Accept`, and `Content-Type` headers for Graph GET/POST operations.
Tests:
- R010-T01: Graph headers include `Authorization`, `Accept`, and `Content-Type`.

R015  Statement: Fail clearly when token configuration is missing.
Design: Raise API error with explicit `OUTLOOK_GRAPH_TOKEN is required` detail when token is blank.
Tests:
- R015-T01: Header construction fails clearly when the token cannot be resolved.

R020  Statement: Expose strict scoped message search with field filters, inclusive date bounds, normalization, AND semantics, bounded limit, and stable retrieval for older date windows.
Design: `GET /v1/messages/search?query=...&limit=...` accepts only scoped tokens (`subject:`, `sender:`, `body:`, `from:`, `to:`). Text matching is case-insensitive and normalizes trim + collapsed whitespace. `body:` matches full message body content (including HTML converted to text). Multiple tokens combine with logical AND. Date filters are inclusive by received date, and unsupported/unscoped tokens return HTTP 400. When `from:` and/or `to:` are present, the Graph request includes a server-side `receivedDateTime` `$filter` and the API follows `@odata.nextLink` pages (bounded scan budget) so messages outside the first Graph page still participate in filtering. Text-only scoped queries keep single-page behavior to avoid unnecessary latency.
Tests:
- R020-T01: Scoped search applies AND semantics and rejects unsupported/unscoped tokens with HTTP 400.

R025  Statement: Move a message to a named folder, creating folder when needed.
Design: Resolve destination folder by display name (case-insensitive), create if absent, then call Graph move API.
Tests:
- R025-T01: Move resolves the destination folder by name, creating it when absent.

R026  Statement: Refresh expired Graph access tokens using a stored refresh token.
Design: Resolve refresh credentials from 1Password and `OUTLOOK_GRAPH_CLIENT_ID`, call Microsoft token endpoint, and persist refreshed tokens to the shared cache file.
Tests:
- R026-T01: Token manager refreshes via the Microsoft token endpoint.

R027  Statement: Retry Graph requests once after a 401 authentication failure.
Design: Invalidate in-memory token state, force refresh, and retry the original Graph request before surfacing an error.
Tests:
- R027-T01: Graph requests retry once after a 401 by force-refreshing the token.

R028  Statement: Persist refreshed OAuth session data to a shared local cache file.
Design: Write access token, refresh token, expiry, and client id to `~/.cache/mailcart/graph_oauth.json` with restrictive permissions.
Tests:
- R028-T01: Refreshed sessions persist to the shared cache with restrictive permissions.

R029  Statement: Restrict token health metadata visibility on the API health endpoint.
Design: `/health` always returns `status: ok`; `token_status` and `token_expires_at` are returned only when the caller supplies a valid write-token header.
Tests:
- R029-T01: Health endpoint exposes token metadata only to authenticated callers.

R030  Statement: Surface Graph auth failures instead of empty search results.
Design: When fallback message fetch fails due to authentication, return explicit 502 auth detail rather than `{"messages": []}`.
Tests:
- R030-T01: Graph auth failures surface a 502 detail instead of empty results.

R035  Statement: Expose a single-message fetch endpoint with body, recipients, and metadata for downstream UIs.
Design: `GET /v1/messages/{message_id}` calls Microsoft Graph `/me/messages/{id}?$select=id,subject,bodyPreview,body,from,toRecipients,receivedDateTime` and returns `{message_id, subject, preview, received_at, sender, recipients, html_body, text_body, body_text}`. The endpoint distinguishes HTML vs plain text body (`html_body` vs `text_body`); `recipients` is a comma-separated list of `toRecipients` addresses. Invalid or malformed `message_id` inputs fail closed with HTTP 404.
Tests:
- R035-T01: Single-message endpoint selects body/recipients/metadata and rejects invalid ids with HTTP 404.

R040  Statement: Start the Matchy Mailcart API over HTTPS only.
Design: API startup resolves TLS cert/key file paths from `MAILCART_MATCHY_TLS_CERT_FILE` and `MAILCART_MATCHY_TLS_KEY_FILE` (with localhost defaults under `~/.mailcart`) and launches uvicorn with `ssl_certfile` and `ssl_keyfile`. Callers must target `https://127.0.0.1:8788` (never `http://`) and supply TLS verification using either `~/.mailcart/matchy-localhost-cert.pem` or a CA bundle that trusts the local mkcert root.
Tests:
- R040-T01: API starts over HTTPS-only uvicorn with TLS cert/key on `127.0.0.1:8788`.

R045  Statement: Fail fast when required API TLS materials are missing.
Design: Startup exits non-zero with explicit guidance when either configured TLS cert or key file does not exist.
Tests:
- R045-T01: Startup fails fast when required TLS materials are missing.

R050  Statement: Match scoped text filters against each message field with a single-pass Aho-Corasick automaton instead of one substring scan per filter.
Design: `AhoCorasick` builds a keyword trie with breadth-first failure links over the union of `subject:`/`sender:`/`body:` filter strings; `search` returns the set of filters occurring as substrings of a field in one O(text + patterns) pass. `_build_criteria_matcher` constructs the automaton once per `/v1/messages/search` request and `_message_matches_criteria` reuses it across every scanned message, preserving the existing case-insensitive, whitespace-normalized AND semantics and inclusive date bounds.
Tests:
- R050-T01: Scoped text filters match via a single-pass Aho-Corasick automaton.

R600  Statement: Classify Graph HTTP responses as authentication failures for retry/refresh handling.
Design: `_is_auth_failure(status_code, body)` returns true for HTTP 401 and known auth-error signatures (`invalidauthenticationtoken`, `authorization_identity_not_found`, `graph auth failed`, or `: 401 `), case-insensitively.
Tests:
- R600-T01: `_is_auth_failure` flags 401 and known invalid-token bodies, not generic errors.

R605  Statement: Issue Graph POST requests through the shared authenticated retry pipeline.
Design: `_graph_post(path, payload)` delegates to `_graph_request("POST", path, payload=payload)` so POST calls inherit token refresh and Graph error mapping behavior.
Tests:
- R605-T01: `_graph_post` calls `_graph_request` with method POST and the payload.

R610  Statement: Parse message `receivedDateTime` values leniently for date filtering.
Design: `_parse_received_at_date(value)` returns `None` for empty input, normalizes trailing `Z` to `+00:00`, parses via `datetime.fromisoformat`, and returns `.date()`; malformed values return `None`.
Tests:
- R610-T01: `_parse_received_at_date` parses ISO/Z dates and returns `None` on blank or malformed input.

R615  Statement: Detect whether the API port is already bound before startup.
Design: `_is_port_in_use(host, port)` opens a TCP socket with a short timeout and reports true iff `connect_ex` succeeds, then closes the socket.
Tests:
- R615-T01: `_is_port_in_use` probes the port via a short-timeout TCP connect.

R620  Statement: Require caller-facing write-token authentication for message API routes.
Design: `/v1/messages/search`, `/v1/messages/{message_id}`, and `/v1/messages/{message_id}/move` require `X-Teller-Write-Token` (configurable via `MAILCART_API_WRITE_TOKEN_HEADER`) and validate it against `MAILCART_API_WRITE_TOKEN` or `TELLER_CLASSIFIER_WRITE_TOKEN` using constant-time comparison. Missing server token config returns HTTP 503; invalid/missing caller token returns HTTP 401.
Tests:
- R620-T01: Message API routes require write-token auth and enforce 503/401 behavior when unconfigured/invalid.

## Changelog

- 2026-05-12: Added script-scoped Matchy API requirements for `scripts/matchy_mailcart_api.py`.
- 2026-05-19: Added OAuth refresh, retry-on-401, cache persistence, health token status, and auth error surfacing requirements.
- 2026-05-19: Added R035 single-message fetch endpoint for downstream UIs (Teller Match Review three-pane view).
- 2026-05-27: Added HTTPS-only startup (R040) and fail-fast TLS material validation (R045) for Matchy Mailcart API.
- 2026-05-28: Updated R020 to strict scoped-token search contract with full-body matching, normalization, inclusive dates, AND semantics, and 400 on unsupported/unscoped tokens.
- 2026-05-29: Updated R020 to require server-side Graph date filters and bounded pagination for date-scoped queries so older-window inbox matches are discoverable beyond the first Graph page.
- 2026-06-03: Clarified R040 caller transport contract (HTTPS-only base URL plus TLS verify bundle requirements) to prevent HTTP/TLS mismatch disconnect loops.
- 2026-06-06: Converted all `Tests:` bullets to numbered `RNNN-Tnn` form for full strict traceability.
- 2026-06-06: Added source-helper requirements R600/R605/R610/R615 for auth classification, POST delegation, date parsing, and port-availability probing.
- 2026-06-07: Tightened `/health` metadata exposure (R029) and added caller-facing write-token auth contract for message routes (R620).
- 2026-06-07: Updated R035 invalid-id behavior to fail closed with HTTP 404.
