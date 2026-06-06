import Foundation

#if canImport(CrashReporter)
import CrashReporter
#endif

// #R001: CrashReporterService exposes a static start() entrypoint that installs PLCrashReporter at launch.
enum CrashReporterService {
    private static let storageDirectoryName = "CrashReports"

    // #R001: Start crash reporter lifecycle setup at application launch.
    static func start() {
#if canImport(CrashReporter)
        guard let crashReporter = makeCrashReporter() else {
            print("CrashReporter: failed to create PLCrashReporter instance")
            return
        }

        persistPendingCrashReportIfPresent(crashReporter)

        do {
            try crashReporter.enableAndReturnError()
        } catch {
            print("CrashReporter: failed to enable reporter: \(error)")
        }

        if ProcessInfo.processInfo.environment["OUTLOOK_MACOS_FORCE_CRASH_ON_LAUNCH"] == "1" {
            fatalError("Intentional crash for PLCrashReporter verification")
        }
#else
        // Keep startup behavior deterministic when the package product is unavailable.
        print("CrashReporter: module unavailable; skipping PLCrashReporter startup")
#endif
    }

#if canImport(CrashReporter)
    // #R010: Configure PLCrashReporter with mach signal handling and build-specific symbolication.
    private static func makeCrashReporter() -> PLCrashReporter? {
        #if DEBUG
        let symbolicationStrategy: PLCrashReporterSymbolicationStrategy = .all
        #else
        let symbolicationStrategy: PLCrashReporterSymbolicationStrategy = []
        #endif

        let config = PLCrashReporterConfig(
            signalHandlerType: .mach,
            symbolicationStrategy: symbolicationStrategy
        )
        return PLCrashReporter(configuration: config)
    }

    // #R005: A pending crash report is loaded, written to disk, and purged on the next launch.
    private static func persistPendingCrashReportIfPresent(_ crashReporter: PLCrashReporter) {
        guard crashReporter.hasPendingCrashReport() else {
            return
        }

        do {
            let data = try crashReporter.loadPendingCrashReportDataAndReturnError()
            let fileURL = try writeCrashReport(data)
            print("CrashReporter: saved pending crash report to \(fileURL.path)")
            crashReporter.purgePendingCrashReport()
        } catch {
            print("CrashReporter: failed handling pending report: \(error)")
        }
    }

    // #R005: Write pending crash report artifacts and metadata to disk.
    private static func writeCrashReport(_ data: Data) throws -> URL {
        let outputDirectory = try crashReportDirectory()
        let basename = "crash-\(timestamp())"

        let crashFileURL = outputDirectory.appendingPathComponent("\(basename).plcrash")
        try data.write(to: crashFileURL, options: .atomic)

        let metadataURL = outputDirectory.appendingPathComponent("\(basename).json")
        let metadata = [
            "bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "captured_at": ISO8601DateFormatter().string(from: Date()),
            "format": "plcrash"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: metadataURL, options: .atomic)

        return crashFileURL
    }

    // #R015: Resolve and create the crash report directory under Application Support.
    private static func crashReportDirectory() throws -> URL {
        let appSupportRoot = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleName = Bundle.main.bundleIdentifier ?? "OutlookMailApp"
        let directory = appSupportRoot
            .appendingPathComponent(bundleName, isDirectory: true)
            .appendingPathComponent(storageDirectoryName, isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // #R020: Generate filename-safe ISO8601 timestamps with fractional seconds.
    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
#endif
}
