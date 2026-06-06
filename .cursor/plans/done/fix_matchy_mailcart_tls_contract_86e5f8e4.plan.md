---
name: fix_matchy_mailcart_tls_contract
overview: Prevent HTTP-to-HTTPS transport mismatches between Matchy and Mailcart by enforcing a single HTTPS contract, validating configuration early, and adding integration tests/diagnostics that fail fast with actionable errors.
todos:
  - id: document-transport-contract
    content: Update Mailcart docs/requirements to codify HTTPS + cert verify contract and troubleshooting guidance.
    status: completed
  - id: add-caller-preflight
    content: Implement caller startup validation for HTTPS scheme, cert file existence, and optional health preflight.
    status: completed
  - id: centralize-http-client
    content: Refactor caller Mailcart HTTP client to one shared base URL + verify configuration with clearer error translation.
    status: completed
  - id: add-regression-tests
    content: Add tests for http rejection, missing cert rejection, valid https acceptance, and TLS-aware health probe.
    status: completed
  - id: rollout-smoke-verify
    content: Define and run rollout smoke checks to confirm pending runs process without transport disconnect loops.
    status: completed
isProject: false
---

# Fix Matchy↔Mailcart Transport Failures

## Goal
Eliminate repeated `Connection aborted` / `RemoteDisconnected` failures by making the Matchy→Mailcart integration explicitly HTTPS-only, cert-aware, and self-validating at startup and in CI.

## Scope
- Ensure callers use `https://127.0.0.1:8788` for Mailcart API operations.
- Ensure TLS verification points to the generated local cert.
- Add fail-fast validation and clear error messaging when URL/cert config is invalid.
- Add regression tests so HTTP misconfiguration is caught before runtime.

## Why This Is Failing
- Mailcart API is already HTTPS-only on port `8788` (`scripts/matchy_mailcart_api.py`).
- A caller in the run-processing path is still using `http://127.0.0.1:8788` (or not supplying TLS verify), which causes the server to close the connection immediately.
- Current behavior surfaces as noisy repeated retry logs instead of a deterministic configuration error.

## Implementation Plan

### 1) Define and document one transport contract
- In Mailcart docs, make the integration contract explicit:
  - Base URL must be `https://127.0.0.1:8788`
  - Cert verify path must be `~/.mailcart/matchy-localhost-cert.pem` (or equivalent configured path)
- Update troubleshooting with exact symptom→cause mapping for `RemoteDisconnected`.
- Target docs:
  - [/Users/phil/local/src/mailcart/README.md](/Users/phil/local/src/mailcart/README.md)
  - [/Users/phil/local/src/mailcart/requirements/matchy_mailcart_api-requirements.md](/Users/phil/local/src/mailcart/requirements/matchy_mailcart_api-requirements.md)

### 2) Add startup/config preflight in the caller (Matchy runner)
- In the run worker/service that polls `/v1/matchy/runs/pending` and calls Mailcart search/move:
  - Parse Mailcart base URL once at startup.
  - Reject non-HTTPS URLs with a clear, single fatal config error.
  - Verify cert file exists/readable before starting worker loop.
  - Optionally execute a one-shot `/health` probe during boot and fail fast on mismatch.
- This prevents endless runtime retries from a known-bad config.
- Target files are in the Matchy repo (outside this workspace), typically runner/http-client config modules.

### 3) Harden request client behavior for local TLS
- Build all Mailcart requests from one shared client/factory:
  - Centralized `base_url` and `verify` settings.
  - No per-call URL concatenation that can drift to `http://`.
- Improve exception translation:
  - Map TLS/transport exceptions to a concise actionable error message (include configured URL and verify path).
  - Suppress repeated duplicate stack noise by emitting one root-cause log and bounded retries.

### 4) Add regression tests
- Add caller-side tests (Matchy repo):
  - Reject `http://127.0.0.1:8788` at startup.
  - Reject missing cert path.
  - Accept valid HTTPS URL + cert path.
  - Verify `/health` preflight is called with TLS verify enabled.
- Add Mailcart-side contract coverage (if needed) to ensure docs/requirements stay aligned:
  - Existing HTTPS-only assumptions in `scripts/matchy_mailcart_api.py` remain validated.

### 5) Operational rollout and verification
- Roll out in this order:
  1. Update caller config + startup validation.
  2. Deploy/restart caller worker.
  3. Confirm healthy `/health` and successful search/move calls.
- Smoke checks:
  - HTTPS health probe succeeds with cert.
  - HTTP probe fails (expected).
  - A pending run processes without `RemoteDisconnected` spam.

## Validation Checklist
- No caller code path uses `http://127.0.0.1:8788`.
- Caller startup fails fast when URL scheme or cert path is invalid.
- Transport exceptions include actionable guidance.
- Tests cover both bad and good config paths.
- Logs no longer show repeated `Connection aborted/RemoteDisconnected` loops under correct config.