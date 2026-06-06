# DAST App Entrypoint Requirements

## Scope

Applies to `dast_app.py`.

R001  Statement: Serve the mailcart FastAPI app over TLS for dynamic security scanning.
Design: `main` imports the `matchy_mailcart_api` app and launches `uvicorn.run` with `ssl_certfile`/`ssl_keyfile` so the DAST lane targets an HTTPS endpoint.
Tests:
- R001-T01: The entrypoint serves the FastAPI app via uvicorn with TLS cert/key.

R005  Statement: Resolve host/port/TLS settings from prioritized environment variables with safe defaults.
Design: `_resolve` walks a prioritized list of env var names and returns the first non-empty value, falling back to a localhost/`8788`/`~/.teller` default when none are set.
Tests:
- R005-T01: `_resolve` returns the first configured env value and falls back to the default otherwise.

## Changelog

- 2026-06-06: Initial requirements doc covering the `dast_app.py` TLS entrypoint for full-coverage traceability.
