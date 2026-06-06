import Foundation

enum MailcartAppLaunchMode: Equatable {
    case normal
    case uiTesting
}

// #R001: Launch mode detection selects UI-testing mode via process arguments or environment.
func detectMailcartLaunchMode(arguments: [String], environment: [String: String]) -> MailcartAppLaunchMode {
    if arguments.contains("--ui-testing") || environment["MAILCART_UI_TEST_MODE"] == "1" {
        return .uiTesting
    }
    return .normal
}

// #R001: ProcessInfo-backed wrapper reuses deterministic argument/environment launch-mode logic.
func detectMailcartLaunchMode(processInfo: ProcessInfo = .processInfo) -> MailcartAppLaunchMode {
    detectMailcartLaunchMode(arguments: processInfo.arguments, environment: processInfo.environment)
}
