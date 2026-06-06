# Verify macOS Crash Reporter Requirements

## Scope

Applies to `scripts/verify_macos_crash_reporter.sh`.

R001  Statement: Run the crash-reporter verification script in strict fail-fast mode.
Design: Script sets strict shell options and exits non-zero on command failures.
Tests:
- R001-T01: Script declares strict fail-fast mode (`set -euo pipefail`).

R005  Statement: Run verification from repository root regardless of caller working directory.
Design: Script resolves repository root from script path and changes into that directory before performing build/launch operations.
Tests:
- R005-T01: Script runs repository-relative commands from repo root regardless of caller directory.

R010  Statement: Verify forced-crash launch path fails non-zero.
Design: Script launches app once with `OUTLOOK_MACOS_FORCE_CRASH_ON_LAUNCH=1` and requires that run to fail.
Tests:
- R010-T01: Script fails when the forced-crash launch exits zero.

R015  Statement: Confirm relaunch run processed pending crash state.
Design: Script relaunches app and treats persistence as observed when it finds `CrashReporter: saved pending crash report to` in launch logs or when it detects fresh crash artifact timestamps.
Tests:
- R015-T01: Script marks crash persistence observed from logs or fresh artifacts.

R020  Statement: Require fresh persisted crash artifacts from current verification run.
Design: Script validates newest `.plcrash` and `.json` outputs exist under configured crash-report directory and are newer than run marker timestamp.
Tests:
- R020-T01: Script requires fresh `.plcrash` and `.json` artifacts newer than the run marker.

R025  Statement: Ensure app build is available before verification launches.
Design: Script runs `make _ui-build` and fails with guidance when build step does not succeed.
Tests:
- R025-T01: Script runs `make _ui-build` and fails with guidance when the build step fails.

R030  Statement: Fail clearly when required local tooling is unavailable.
Design: Script checks for `make` availability and validates resolved app executable path is executable before launch attempts.
Tests:
- R030-T01: Script fails clearly when required tooling or the app executable is unavailable.

R035  Statement: Emit clear success output that includes persisted artifact paths.
Design: On successful verification, script prints success banner plus resolved `.plcrash` and `.json` file locations.
Tests:
- R035-T01: Successful verification prints a success banner with persisted artifact paths.

R040  Statement: Support caller-provided configuration overrides for local/CI execution.
Design: Script accepts `APP_EXECUTABLE`, `CRASH_REPORT_DIR`, and `STARTUP_WAIT_SECONDS` environment overrides and uses them for launch and validation.
Tests:
- R040-T01: Script honors `APP_EXECUTABLE`, `CRASH_REPORT_DIR`, and `STARTUP_WAIT_SECONDS` overrides.

## Changelog

- 2026-05-12: Added script-scoped crash reporter requirements for `scripts/verify_macos_crash_reporter.sh`.
