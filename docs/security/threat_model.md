# Mailcart Threat Model

## Scope

Mailcart includes:

- a localhost HTTPS API used by Matchy (`scripts/matchy_mailcart_api.py`),
- native bridge code that talks to Microsoft Graph,
- Swift UI rendering for message content.

## Trust Boundaries

1. **Caller Boundary**: local process calling the loopback API.
2. **Credential Boundary**: Graph tokens from `1psa`/env/cache.
3. **Network Boundary**: outbound HTTPS requests to Microsoft Graph.
4. **UI Boundary**: untrusted message HTML rendered in `WKWebView`.

## Primary Threats

### Unauthenticated Local API Access

- Risk: another local process could read/move mail without approval.
- Mitigation: message routes require a caller write-token header validated with constant-time compare.

### Token Disclosure Via Health Endpoint

- Risk: token metadata visible to any localhost caller.
- Mitigation: `/health` always returns only `status`; token metadata is included only with valid auth.

### Pagination Host Injection

- Risk: malicious `@odata.nextLink` could redirect native bridge requests.
- Mitigation: native pagination cursor handling now enforces Graph HTTPS host/path checks.

### HTML Email Active Content

- Risk: email HTML can trigger active/scripted behavior in desktop web view.
- Mitigation: non-persistent web data store, JavaScript disabled, restrictive CSP, and navigation blocking.

## Residual Risks

- Device-code/OAuth flow remains user-driven and local.
- Token cache remains disk-backed for compatibility; FileVault and keychain/1Password practices still required.
