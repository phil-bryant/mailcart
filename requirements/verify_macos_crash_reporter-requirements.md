# Verify macOS Crash Reporter Requirements

## Scope

Applies to `scripts/verify_macos_crash_reporter.sh`.

R001  Statement: Run the crash-reporter verification script in strict fail-fast mode.
Design: Script sets strict shell options and exits non-zero on command failures.
Tests:
- Verify script declares strict mode (`set -euo pipefail`).
- Introduce a failing command path and verify script exits non-zero.

R005  Statement: Run verification from repository root regardless of caller working directory.
Design: Script resolves repository root from script path and changes into that directory before performing build/launch operations.
Tests:
- Run script from an alternate working directory and verify it still executes repository-relative commands.
- Verify relative `make` and app executable paths are resolved from repository root.

R010  Statement: Verify forced-crash launch path fails non-zero.
Design: Script launches app once with `OUTLOOK_MACOS_FORCE_CRASH_ON_LAUNCH=1` and requires that run to fail.
Tests:
- Stub app executable to return non-zero when forced crash variable is set and verify script continues.
- Stub app executable to return zero during forced-crash run and verify script fails with clear guidance.

R015  Statement: Confirm relaunch run processed pending crash state.
Design: Script relaunches app and treats persistence as observed when it finds `CrashReporter: saved pending crash report to` in launch logs or when it detects fresh crash artifact timestamps.
Tests:
- Stub relaunch output to include the persistence log line and verify script marks persistence observed.
- Stub relaunch artifact creation and verify script accepts fresh artifact timestamps.

R020  Statement: Require fresh persisted crash artifacts from current verification run.
Design: Script validates newest `.plcrash` and `.json` outputs exist under configured crash-report directory and are newer than run marker timestamp.
Tests:
- Create fresh artifacts after relaunch and verify script passes.
- Leave artifacts stale or missing and verify script fails non-zero.

R025  Statement: Ensure app build is available before verification launches.
Design: Script runs `make _ui-build` and fails with guidance when build step does not succeed.
Tests:
- Stub `make _ui-build` success and verify script proceeds to launch checks.
- Stub `make _ui-build` failure and verify script exits non-zero with build guidance.

R030  Statement: Fail clearly when required local tooling is unavailable.
Design: Script checks for `make` availability and validates resolved app executable path is executable before launch attempts.
Tests:
- Run without `make` on `PATH` and verify script exits with tooling guidance.
- Provide non-executable app path and verify script exits with missing-executable guidance.

R035  Statement: Emit clear success output that includes persisted artifact paths.
Design: On successful verification, script prints success banner plus resolved `.plcrash` and `.json` file locations.
Tests:
- Run successful verification and verify success banner is printed.
- Verify output includes both crash report and metadata artifact paths.

R040  Statement: Support caller-provided configuration overrides for local/CI execution.
Design: Script accepts `APP_EXECUTABLE`, `CRASH_REPORT_DIR`, and `STARTUP_WAIT_SECONDS` environment overrides and uses them for launch and validation.
Tests:
- Provide override paths and wait value and verify script uses them during execution.
- Verify default values are used when overrides are not supplied.

## Changelog

- 2026-05-12: Added script-scoped crash reporter requirements for `scripts/verify_macos_crash_reporter.sh`.
