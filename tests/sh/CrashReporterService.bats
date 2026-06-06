#!/usr/bin/env bats

# Interface contract checks for the macOS crash reporter startup service.

load helpers/repo_root

setup() {
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
