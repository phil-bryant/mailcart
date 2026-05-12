import SwiftUI
import AppKit

// #R001: Launch Outlook mail experience from SwiftUI app entrypoint.
// #R005: Enforce minimum desktop window size suitable for split-mail workflow.
// #R010: Root the app scene in split-navigation mailbox UI.
// #R015: Route search-field edits through the view-model query update path.
// #R020: Surface active search progress in mailbox column UI.
// #R025: Render selectable summary results keyed by message identity.
// #R030: Display subject/preview hierarchy in mailbox summary rows.
// #R035: Trigger message loads when non-empty selection changes.
// #R040: Render selected mailcart metadata and body content clearly.
// #R045: Show empty-state prompt when no mailcart is selected.
// #R050: Use main-actor observable UI state from the view model.
// #R055: Debounce and cancel superseded search requests.
// #R060: Map bridge read/search responses into published UI state.
// #R065: Ensure initial mailbox load begins as soon as UI launches.
// #R070: Support load-more pagination controls in mailbox workflow.
// #R075: Host rendered/raw body mode UI with rendered as default.
// #R080: Support attachment list/open UI interactions.
// #R085: Support user-selectable mailbox sorting controls.
// #R090: Terminate app lifecycle when last window closes.
// #R095: Surface mailbox error states from view-model state.
final class OutlookMailApplicationDelegate: NSObject, NSApplicationDelegate {
    // #R090: Close-window behavior must terminate process for make-run lifecycle.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct OutlookMailApp: App {
    @NSApplicationDelegateAdaptor(OutlookMailApplicationDelegate.self) private var applicationDelegate

    init() {
        CrashReporterService.start()
    }

    var body: some Scene {
        WindowGroup {
            OutlookMailContentView()
                .frame(minWidth: 980, minHeight: 620)
        }
    }
}
