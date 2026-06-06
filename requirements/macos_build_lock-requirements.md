# macOS Build Lock Requirements

## Scope

Applies to `scripts/macos_build_lock.sh`.

R001  Statement: Apply a secure umask for lanes that source the shared build lock.
Design: The sourced helper sets `umask 007` so build artifacts created under the lock are not world-readable.
Tests:
- R001-T01: The helper sets a secure `umask 007`.

R005  Statement: Serialize the macOS build critical section with a robust mutual-exclusion lock.
Design: `with_macos_build_lock` acquires a `mkdir`-based lock directory, reclaims a stale lock whose owner PID is no longer running, and times out after a bounded wait.
Tests:
- R005-T01: The lock is acquired via `mkdir`, reclaims stale owners, and enforces a timeout.

R010  Statement: Run the wrapped command under the lock and propagate its exit status.
Design: After acquiring the lock the helper runs `"$@"`, captures its status, releases the lock, clears the trap, and returns the captured status.
Tests:
- R010-T01: The wrapped command runs under the lock and its exit status is propagated after release.

## Changelog

- 2026-06-06: Initial requirements doc covering the `scripts/macos_build_lock.sh` build serialization helper for full-coverage traceability.
