# 05 Install Matchy API TLS Requirements

## Scope

Applies to `05_install_matchy_api_tls.sh`.

R001  Statement: Configure deterministic defaults for Matchy API TLS material locations.
Design: Resolve TLS directory, certificate, and key paths from `MAILCART_MATCHY_TLS_*` environment variables with stable defaults under `~/.mailcart`.
Tests:
- Run script with default environment and verify expected default cert/key path output.
- Override `MAILCART_MATCHY_TLS_*` values and verify printed target paths match overrides.

R005  Statement: Preserve existing trusted TLS materials unless explicit replacement is required.
Design: Reuse existing cert/key files by default, but regenerate when force flag is enabled or when existing cert appears self-signed legacy material.
Tests:
- Provide existing cert/key and verify script exits without regeneration.
- Set `MAILCART_MATCHY_TLS_FORCE_REGENERATE=true` and verify regeneration path is taken.

R010  Statement: Require `mkcert` for localhost certificate generation.
Design: Fail clearly when `mkcert` is unavailable and instruct operator to run prerequisites installer first.
Tests:
- Run script without `mkcert` on `PATH` and verify explicit failure message and non-zero exit.

R015  Statement: Generate localhost TLS materials with restrictive file permissions.
Design: Generate cert/key for `localhost`, `127.0.0.1`, and `::1`, then apply owner-only permissions (`chmod 600`) to cert/key and secure directory permissions (`chmod 700`).
Tests:
- Run script with `mkcert` available and verify cert/key files are generated.
- Verify generated files and containing directory have restrictive permissions.

## Changelog

- 2026-05-27: Added requirements for `05_install_matchy_api_tls.sh` TLS bootstrap behavior and regeneration policy.
