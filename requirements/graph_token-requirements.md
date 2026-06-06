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

## Changelog

- 2026-06-06: Initial requirements doc covering the `scripts/graph_token.py` OAuth token lifecycle for full-coverage traceability.
