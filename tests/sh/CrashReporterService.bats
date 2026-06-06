#!/usr/bin/env bats

# Interface contract checks for the macOS crash reporter startup service.

load helpers/repo_root

setup() {
  #R001: Test harness setup for CrashReporterService contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/macos_app/UI/CrashReporterService.swift"
}

@test "R001: CrashReporterService exposes a static start() entrypoint" {
  #R001-T01: CrashReporterService exposes a static start() entrypoint that installs the crash reporter.
  run rg -F "enum CrashReporterService {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "static func start() {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "return PLCrashReporter(configuration: config)" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: pending crash report is persisted then purged" {
  #R005-T01: A pending crash report is written to disk and then purged via purgePendingCrashReport().
  run rg -F "private static func persistPendingCrashReportIfPresent(_ crashReporter: PLCrashReporter)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "crashReporter.purgePendingCrashReport()" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R010: crash reporter builder configures mach handler and symbolication strategy" {
  #R010-T01: makeCrashReporter() configures mach signal handling and build-dependent symbolication strategy.
  run rg -F "private static func makeCrashReporter() -> PLCrashReporter?" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "signalHandlerType: .mach" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "symbolicationStrategy" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R015: crash report directory resolves under Application Support and is created" {
  #R015-T01: Crash report directory resolution uses Application Support and creates bundle-scoped CrashReports directories.
  run rg -F "private static func crashReportDirectory() throws -> URL" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F ".applicationSupportDirectory" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "storageDirectoryName" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R020: timestamp formatter emits filename-safe fractional-seconds ISO8601" {
  #R020-T01: Timestamp generation uses fractional-seconds ISO8601 output with colon replacement for filename safety.
  run rg -F "private static func timestamp() -> String" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F ".withFractionalSeconds" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "replacingOccurrences(of: \":\", with: \"-\")" "${SRC}"
  [ "$status" -eq 0 ]
}
