# Graph Token Lifecycle Requirements

## Scope

Applies to `scripts/graph_token.py`.

R005  Statement: Accept tokens with or without a leading `Bearer ` prefix.
Design: `_normalize_token` strips a leading `Bearer ` segment (and stray surrounding quotes) before any token value is stored or used.
Tests:
- R005-T01: `_normalize_token` strips a leading `Bearer ` prefix and surrounding quotes.

R026  Statement: Refresh expired Graph access tokens using a stored refresh token.
Design: `GraphTokenManager.refresh` posts a `refresh_token` grant to the Microsoft token endpoint, validates the response, and returns a refreshed `TokenSession`.
Tests:
- R026-T01: `refresh` posts a refresh_token grant to the Microsoft token endpoint and returns a refreshed session.

R028  Statement: Persist refreshed OAuth session data to a shared local cache file with restrictive permissions.
Design: `GraphTokenManager.persist` writes the session JSON atomically (temp file + `os.replace`) to `~/.cache/mailcart/graph_oauth.json` with `0o600` permissions.
Tests:
- R028-T01: `persist` writes the cache atomically with `0o600` permissions.

R030  Statement: Decode JWT expiry (`exp`) claims into epoch timestamps.
Design: `jwt_expires_at` base64url-decodes the JWT payload, reads `exp`, and returns `None` for malformed tokens or missing claims.
Tests:
- R030-T01: `jwt_expires_at` decodes a valid `exp` claim and returns `None` for malformed tokens.

R032  Statement: Resolve Graph credentials from 1Password with normalized token values.
Design: `_read_psa_field` shells out to `1psa`, normalizes token text, and is used by `_access_token_from_psa`, `_refresh_token_from_psa`, and `_client_id` fallback behavior.
Tests:
- R032-T01: 1Password field resolution normalizes output and raises when `1psa` is unavailable.

R034  Statement: Treat token sessions as valid only when access tokens remain outside refresh buffer.
Design: `TokenSession.is_valid` requires a non-empty access token and an expiry beyond `now + REFRESH_BUFFER_SECONDS`.
Tests:
- R034-T01: Session validity requires non-empty access token and expiry beyond the refresh buffer.

R036  Statement: Round-trip token sessions to/from cache dictionaries with safe coercions.
Design: `TokenSession.to_dict` serializes fields and `from_dict` normalizes token prefixes while coercing integer/string payload values.
Tests:
- R036-T01: Token session dictionary round-trip preserves normalized access/refresh/client/expiry values.

R038  Statement: Initialize and invalidate manager in-memory session state deterministically.
Design: `GraphTokenManager.__init__` stores cache path/session fields and `invalidate` clears the in-memory session.
Tests:
- R038-T01: Manager initialization honors explicit cache path and `invalidate` clears in-memory session state.

R040  Statement: Report Graph token health metadata from current session state.
Design: `token_status` classifies valid/expired/missing/missing_refresh_token outcomes from `load()` and maps error details.
Tests:
- R040-T01: Token status reports valid/expired/missing/missing_refresh_token states from crafted manager sessions.

R042  Statement: Load valid token sessions from memory/cache/bootstrap with refresh fallback.
Design: `load` prefers valid in-memory or cached sessions, then bootstraps/persists fresh values, and refreshes when only refresh_token is available.
Tests:
- R042-T01: `load` returns valid cached sessions without forcing bootstrap/refresh when cache is valid.

R044  Statement: Return usable access tokens by forcing refresh when loaded sessions are expired.
Design: `get_access_token` returns a valid loaded token, or triggers forced refresh when the session has a refresh token but expired access token.
Tests:
- R044-T01: `get_access_token` triggers forced refresh for expired sessions and returns refreshed access tokens.

R046  Statement: Read OAuth cache files defensively across missing/empty/corrupt data states.
Design: `_read_cache` returns `None` for missing, malformed, or empty cache payloads and normalizes recovered session/client-id values.
Tests:
- R046-T01: `_read_cache` returns `None` for missing/corrupt payloads and returns normalized sessions for valid cache data.

R048  Statement: Bootstrap sessions from environment, cache, and 1Password credential sources.
Design: `_bootstrap_session` composes token/client fields from env/cache first, then fills missing refresh/access values via 1Password lookups.
Tests:
- R048-T01: `_bootstrap_session` prioritizes env/cache values and fills missing credentials from 1Password lookups.

R052  Statement: Resolve configurable 1Password item and field names with defaults.
Design: `_psa_item`, `_psa_access_field`, `_psa_refresh_field`, and `_psa_client_id_field` read override env vars and fall back to default constants.
Tests:
- R052-T01: PSA item/field helpers honor environment overrides and default values when unset.

R054  Statement: Expose a process-wide Graph token manager singleton.
Design: `get_manager` returns `_DEFAULT_MANAGER` for shared lifecycle use across API entrypoints.
Tests:
- R054-T01: `get_manager()` returns the same singleton manager instance on repeated calls.

## Changelog

- 2026-06-06: Initial requirements doc covering the `scripts/graph_token.py` OAuth token lifecycle for full-coverage traceability.
- 2026-06-06: Added R030–R054 for JWT expiry decode, PSA resolution, session lifecycle, status/load/bootstrap behavior, and singleton manager access.
