import Foundation

// #R001: Provide app-launched view-model behavior for Outlook mail flow.
// #R005: Support minimum-size workflow by exposing state for split mail UX.
// #R010: Supply state consumed by split mailbox/detail navigation UI.
// #R015: Accept search-field updates through explicit query mutation API.
// #R020: Publish active search progress state during search execution.
// #R025: Publish searchable summary results keyed by message identity.
// #R030: Preserve summary subject/preview hierarchy from bridge outputs.
// #R035: Load full mailcart content on selected message requests.
// #R040: Publish selected mailcart metadata/body for detail rendering.
// #R045: Preserve nil-selected-mailcart state for empty detail prompt.
// #R050: Maintain main-actor observable state for query/search/detail fields.
// #R055: Debounce and cancel superseded search requests.
// #R060: Map bridge read/search responses into published state.
// #R065: Trigger startup mailbox load during view-model initialization.
// #R070: Track pagination cursor and append load-more results.
// #R075: Support rendered/raw body-mode behavior through selected-mailcart fields.
// #R080: Route attachment open actions through the bridge API.
// #R085: Provide deterministic subject/date sorting options.
// #R090: Support close-to-terminate lifecycle by keeping state consistent.
// #R095: Publish actionable mailbox error messages.
@MainActor
final class OutlookMailViewModel: ObservableObject {
    enum MailSortOption: String, CaseIterable {
        case dateReceived = "Date received"
        case subject = "Subject"
    }

    @Published var query: String = ""
    @Published private(set) var summaries: [OutlookMailcartSummaryDTO] = []
    @Published private(set) var selectedMailcart: OutlookMailcartDTO?
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var errorMessage: String?
    @Published var sortOption: MailSortOption = .dateReceived

    private let bridge: OutlookClientBridge
    private var searchTask: Task<Void, Never>?
    private var nextCursor: String = ""
    private var latestSearchGeneration: Int = 0

    var canLoadMore: Bool {
        let canLoad = nextCursor.isEmpty == false && isSearching == false && isLoadingMore == false
        return canLoad
    }

    init(bridge: OutlookClientBridge = OutlookClientBridge()) {
        self.bridge = bridge
        // #R065: Initial load starts immediately without requiring query edits.
        scheduleSearch(isInitialLoad: true)
    }

    func updateQuery(_ value: String) {
        query = value
        scheduleSearch(isInitialLoad: false)
    }

    func updateSortOption(_ value: MailSortOption) {
        sortOption = value
        applySortToSummaries()
    }

    func loadMailcart(messageId: String) {
        let result = bridge.readMailcart(withMessageId: messageId)
        selectedMailcart = result
    }

    func loadMoreMailcarts() {
        // #R070: Load additional server pages when continuation cursor exists.
        if canLoadMore {
            isLoadingMore = true
            let cursorToLoad = nextCursor
            let generation = latestSearchGeneration
            searchTask = Task { [weak self] in
                guard let self else { return }
                await self.fetchPage(cursor: cursorToLoad, appendResults: true, generation: generation)
                await MainActor.run {
                    self.isLoadingMore = false
                }
            }
        }
    }

    func openAttachment(_ attachment: OutlookAttachmentDTO) {
        // #R080: Open requested attachment from selected message context.
        if let mailcart = selectedMailcart {
            let opened = bridge.openAttachment(
                withMessageId: mailcart.messageId,
                attachmentId: attachment.attachmentId,
                fileName: attachment.fileName
            )
            if !opened {
                errorMessage = "Could not open attachment \(attachment.fileName)."
            }
        }
    }

    private func scheduleSearch(isInitialLoad: Bool) {
        latestSearchGeneration += 1
        let generation = latestSearchGeneration
        let shouldDebounce = !isInitialLoad
        searchTask?.cancel()
        isSearching = true
        isLoadingMore = false
        nextCursor = ""
        errorMessage = graphTokenMissingErrorMessage()

        searchTask = Task { [weak self] in
            guard let self else { return }
            if shouldDebounce {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            await self.fetchPage(cursor: "", appendResults: false, generation: generation)
        }
    }

    private func fetchPage(cursor: String, appendResults: Bool, generation: Int) async {
        let result = bridge.searchMailcarts(withQuery: query, limit: 50, cursor: cursor)
        let isLatestGeneration = generation == latestSearchGeneration
        if Task.isCancelled == false && isLatestGeneration {
            if appendResults {
                summaries.append(contentsOf: result.summaries)
            } else {
                summaries = result.summaries
            }
            nextCursor = result.nextCursor
            let bridgeError = result.errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if bridgeError.isEmpty == false {
                errorMessage = bridgeError
            } else {
                errorMessage = nil
            }
            applySortToSummaries()
            isSearching = false
        }
    }

    private func applySortToSummaries() {
        // #R085: Subject sort is alphabetical; date sort is newest-first.
        if sortOption == .subject {
            summaries.sort { lhs, rhs in
                lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
            }
        } else {
            summaries.sort { lhs, rhs in
                lhs.receivedAt > rhs.receivedAt
            }
        }
    }

    private func graphTokenMissingErrorMessage() -> String? {
        // #R095: Show actionable token setup guidance when startup cannot load.
        let environment = ProcessInfo.processInfo.environment
        let token = environment["OUTLOOK_GRAPH_TOKEN"] ?? ""
        let message: String?
        if token.isEmpty {
            message = "Missing OUTLOOK_GRAPH_TOKEN. Configure token and relaunch with make run."
        } else {
            message = nil
        }
        return message
    }
}
