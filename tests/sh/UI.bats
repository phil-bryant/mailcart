#!/usr/bin/env bats

load helpers/repo_root

setup() {
  #R001: Test harness setup for UI contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  UI_DIR="${REPO_ROOT}/macos_app/UI"
  APP_FILE="${UI_DIR}/OutlookMailApp.swift"
  VIEW_FILE="${UI_DIR}/OutlookMailContentView.swift"
  MODEL_FILE="${UI_DIR}/OutlookMailViewModel.swift"
  HTML_FILE="${UI_DIR}/HTMLBodyView.swift"
}

@test "R001: app entrypoint hosts a single WindowGroup rooted at the content view" {
  #R001-T01: OutlookMailApp is the @main app exposing a single WindowGroup rooted at OutlookMailContentView.
  run rg -F "@main" "${APP_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "struct OutlookMailApp: App" "${APP_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "WindowGroup {" "${APP_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "OutlookMailContentView()" "${APP_FILE}"
  [ "$status" -eq 0 ]
}

@test "R005: root content enforces the minimum split-mail window frame" {
  #R005-T01: Root content applies a minimum window frame of 980 width and 620 height.
  run rg -F ".frame(minWidth: 980, minHeight: 620)" "${APP_FILE}"
  [ "$status" -eq 0 ]
}

@test "R010: content uses split navigation with the Outlook primary title" {
  #R010-T01: OutlookMailContentView uses NavigationSplitView with the Outlook primary navigation title.
  run rg -F "NavigationSplitView {" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F '.navigationTitle("Outlook")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}

@test "R015: search field binds writes through the view-model query mutation" {
  #R015-T01: The Search Outlook mail field delegates writes through viewModel.updateQuery(_:).
  run rg -F 'TextField("Search Outlook mail"' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "set: { value in viewModel.updateQuery(value) }" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "func updateQuery(_ value: String)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R020: mailbox surfaces active search progress while searching" {
  #R020-T01: A Searching ProgressView renders while viewModel.isSearching is true.
  run rg -F "if viewModel.isSearching {" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F 'ProgressView("Searching' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "@Published private(set) var isSearching: Bool = false" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R025: summary list is keyed and tagged by message id for selection" {
  #R025-T01: The summary list keys on viewModel.summaries messageId and tags each row by id.
  run rg -F "List(viewModel.summaries, id: \\.messageId, selection: \$selectedMessageId)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F ".tag(summary.messageId)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}

@test "R030: summary rows show one-line subject headline and two-line secondary preview" {
  #R030-T01: Summary rows show a one-line subject headline and a two-line secondary preview.
  run rg -F "Text(summary.subject)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F ".lineLimit(1)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "Text(summary.preview)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F ".lineLimit(2)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}

@test "R035: non-empty selection changes trigger a detail load" {
  #R035-T01: A non-empty selection change invokes viewModel.loadMailcart(messageId:).
  run rg -F ".onChange(of: selectedMessageId)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "if messageId.isEmpty == false {" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "viewModel.loadMailcart(messageId: messageId)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}

@test "R040: detail pane renders subject, From/To/Received metadata, and selectable body" {
  #R040-T01: Detail pane renders subject, From/To/Received metadata, and a selection-enabled body.
  run rg -F 'Text("From: \(mailcart.sender)")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F 'Text("To: \(mailcart.recipient)")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F 'Text("Received: \(mailcart.receivedAt)")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F ".textSelection(.enabled)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}

@test "R045: empty selection renders the envelope empty-state prompt" {
  #R045-T01: With no selection the detail pane shows the envelope.open empty-state prompt.
  run rg -F 'Image(systemName: "envelope.open")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F 'Text("Select an email")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "if let mailcart = viewModel.selectedMailcart {" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}

@test "R050: view model is a main-actor observable with private-set published state" {
  #R050-T01: OutlookMailViewModel is a @MainActor observable with private-set published state.
  run rg -F "@MainActor" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "final class OutlookMailViewModel: ObservableObject" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "@Published var query: String" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "@Published private(set) var summaries:" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "@Published private(set) var selectedMailcart:" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R055: search is debounced 250ms and cancels superseded tasks at limit 50" {
  #R055-T01: scheduleSearch cancels prior tasks, waits 250ms, and searches with limit: 50.
  run rg -F "func scheduleSearch(isInitialLoad: Bool)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "searchTask?.cancel()" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "Task.sleep(nanoseconds: 250_000_000)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "limit: 50" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R060: view model performs bridge search/read off the main actor" {
  #R060-T01: Bridge read/search work runs off the main actor and maps results into published UI state.
  run rg -F 'private let bridgeQueue = DispatchQueue(label: "mailcart.outlook-bridge-queue"' "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "let result = await self.readMailcartFromBridge(messageId: messageId)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "let result = await searchMailcartsFromBridge(query: queryAtRequestTime, cursor: cursor)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R065: view model schedules an initial mailbox load from init" {
  #R065-T01: The view-model init schedules an initial mailbox load via scheduleSearch(isInitialLoad: true).
  run rg -F "init(bridge: OutlookBridgeClient? = nil)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "scheduleSearch(isInitialLoad: true)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R070: mailbox exposes a cursor-backed load-more action" {
  #R070-T01: A cursor-backed Load more emails action appends summaries when canLoadMore is true.
  run rg -F 'Text("Load more emails")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "func loadMoreMailcarts()" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "var canLoadMore: Bool {" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "private var nextCursor: String" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R075: detail body mode defaults to rendered HTML with a raw toggle" {
  #R075-T01: Detail body mode defaults to rendered HTMLBodyView with a raw-source toggle.
  run rg -F "bodyDisplayMode: BodyDisplayMode = .rendered" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "HTMLBodyView(html: htmlBody)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "private func rawBodyView(mailcart: OutlookMailcartDTO)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "import WebKit" "${HTML_FILE}"
  [ "$status" -eq 0 ]
}

@test "R080: detail lists attachments and routes Open through the bridge" {
  #R080-T01: Detail lists attachment metadata and routes each Open action through the bridge.
  run rg -F 'Text("Attachments")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F 'Button("Open") {' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "viewModel.openAttachment(attachment)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "bridge.openAttachment(" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R085: mailbox sorts by subject ascending or received date descending" {
  #R085-T01: Mailbox sorting orders by subject ascending or received date descending.
  run rg -F "func applySortToSummaries()" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "if sortOption == .subject {" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "lhs.receivedAt > rhs.receivedAt" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R090: app delegate terminates the process after the last window closes" {
  #R090-T01: The app delegate terminates the process after the last window closes.
  run rg -F "func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool" "${APP_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "NSApplicationDelegateAdaptor(OutlookMailApplicationDelegate.self)" "${APP_FILE}"
  [ "$status" -eq 0 ]
}

@test "R095: view model surfaces actionable mailbox error messaging inline" {
  #R095-T01: The view-model surfaces an actionable mailbox errorMessage rendered inline in the UI.
  run rg -F "@Published private(set) var errorMessage: String?" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "func graphTokenMissingErrorMessage() -> String?" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "Missing OUTLOOK_GRAPH_TOKEN." "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "Text(error)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}
