# CrashReporterService Requirements

## Scope

Applies to `macos_app/UI/CrashReporterService.swift`.

R001  Statement: Provide a crash-reporting startup entrypoint for the macOS app.
Design: `CrashReporterService` is an enum exposing a static `start()` that creates a `PLCrashReporter` instance and enables it during launch when the CrashReporter module is available.
Tests:
- R001-T01: `CrashReporterService` exposes a static `start()` entrypoint that installs the crash reporter.

R005  Statement: Persist and clear any crash report captured during the previous session.
Design: `persistPendingCrashReportIfPresent` loads the pending crash report data, writes it to the crash report directory, and purges the pending report from PLCrashReporter.
Tests:
- R005-T01: A pending crash report is written to disk and then purged via `purgePendingCrashReport()`.

## Changelog

- 2026-06-06: Initial requirements doc covering `macos_app/UI/CrashReporterService.swift` crash-report startup and persistence.
