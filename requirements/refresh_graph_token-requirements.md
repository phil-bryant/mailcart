# Refresh Graph Token CLI Requirements

## Scope

Applies to `scripts/refresh_graph_token.py`.

R001  Statement: Provide a CLI that refreshes or validates the shared Graph OAuth token cache.
Design: `main` parses a `--force` flag; with `--force` it invalidates, loads, and force-refreshes the session, otherwise it resolves a valid access token via the shared `GraphTokenManager`.
Tests:
- R001-T01: CLI parses `--force` and refreshes/validates the cache through the shared token manager.

R005  Statement: Report token failures clearly with a non-zero exit code.
Design: `GraphTokenError` is caught, printed to stderr, and surfaced as a non-zero return so callers detect refresh failures.
Tests:
- R005-T01: Token errors are printed to stderr and surfaced as a non-zero exit code.

## Changelog

- 2026-06-06: Initial requirements doc covering the `scripts/refresh_graph_token.py` CLI for full-coverage traceability.
