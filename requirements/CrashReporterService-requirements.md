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

R010  Statement: Configure crash reporting with mach signal handling and build-specific symbolication settings.
Design: `makeCrashReporter` chooses `.all` symbolication in debug builds, `[]` in release builds, and instantiates `PLCrashReporterConfig(signalHandlerType: .mach, symbolicationStrategy: ...)`.
Tests:
- R010-T01: `makeCrashReporter()` configures mach signal handling and build-dependent symbolication strategy.

R015  Statement: Resolve and create the crash-report output directory under Application Support.
Design: `crashReportDirectory` resolves `.applicationSupportDirectory`, appends bundle id and `CrashReports`, and creates missing intermediate directories.
Tests:
- R015-T01: Crash report directory resolution uses Application Support and creates bundle-scoped `CrashReports` directories.

R020  Statement: Generate filename-safe ISO8601 timestamps for crash artifact basenames.
Design: `timestamp` uses `ISO8601DateFormatter` with fractional seconds and replaces `:` with `-` for filesystem-safe names.
Tests:
- R020-T01: Timestamp generation uses fractional-seconds ISO8601 output with colon replacement for filename safety.

## Changelog

- 2026-06-06: Initial requirements doc covering `macos_app/UI/CrashReporterService.swift` crash-report startup and persistence.
- 2026-06-06: Added R010/R015/R020 for crash-reporter configuration, output directory resolution, and timestamp formatting.
