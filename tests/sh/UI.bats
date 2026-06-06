#!/usr/bin/env bats

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  UI_DIR="${REPO_ROOT}/macos_app/UI"
  APP_FILE="${UI_DIR}/OutlookMailApp.swift"
  VIEW_FILE="${UI_DIR}/OutlookMailContentView.swift"
  MODEL_FILE="${UI_DIR}/OutlookMailViewModel.swift"
  HTML_FILE="${UI_DIR}/HTMLBodyView.swift"
}

@test "R001: app entrypoint hosts a single WindowGroup rooted at the content view" {
  #R001
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
  #R005
  run rg -F ".frame(minWidth: 980, minHeight: 620)" "${APP_FILE}"
  [ "$status" -eq 0 ]
}

@test "R010: content uses split navigation with the Outlook primary title" {
  #R010
  run rg -F "NavigationSplitView {" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F '.navigationTitle("Outlook")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}

@test "R015: search field binds writes through the view-model query mutation" {
  #R015
  run rg -F 'TextField("Search Outlook mail"' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "set: { value in viewModel.updateQuery(value) }" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "func updateQuery(_ value: String)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R020: mailbox surfaces active search progress while searching" {
  #R020
  run rg -F "if viewModel.isSearching {" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F 'ProgressView("Searching' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "@Published private(set) var isSearching: Bool = false" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R025: summary list is keyed and tagged by message id for selection" {
  #R025
  run rg -F "List(viewModel.summaries, id: \\.messageId, selection: \$selectedMessageId)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F ".tag(summary.messageId)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}

@test "R030: summary rows show one-line subject headline and two-line secondary preview" {
  #R030
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
  #R035
  run rg -F ".onChange(of: selectedMessageId)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "if messageId.isEmpty == false {" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "viewModel.loadMailcart(messageId: messageId)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}

@test "R040: detail pane renders subject, From/To/Received metadata, and selectable body" {
  #R040
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
  #R045
  run rg -F 'Image(systemName: "envelope.open")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F 'Text("Select an email")' "${VIEW_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "if let mailcart = viewModel.selectedMailcart {" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}

@test "R050: view model is a main-actor observable with private-set published state" {
  #R050
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
  #R055
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
  #R060
  run rg -F 'private let bridgeQueue = DispatchQueue(label: "mailcart.outlook-bridge-queue"' "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "let result = await self.readMailcartFromBridge(messageId: messageId)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "let result = await searchMailcartsFromBridge(query: queryAtRequestTime, cursor: cursor)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R065: view model schedules an initial mailbox load from init" {
  #R065
  run rg -F "init(bridge: OutlookBridgeClient? = nil)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "scheduleSearch(isInitialLoad: true)" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
}

@test "R070: mailbox exposes a cursor-backed load-more action" {
  #R070
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
  #R075
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
  #R080
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
  #R085
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
  #R090
  run rg -F "func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool" "${APP_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "NSApplicationDelegateAdaptor(OutlookMailApplicationDelegate.self)" "${APP_FILE}"
  [ "$status" -eq 0 ]
}

@test "R095: view model surfaces actionable mailbox error messaging inline" {
  #R095
  run rg -F "@Published private(set) var errorMessage: String?" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "func graphTokenMissingErrorMessage() -> String?" "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "Missing OUTLOOK_GRAPH_TOKEN." "${MODEL_FILE}"
  [ "$status" -eq 0 ]
  run rg -F "Text(error)" "${VIEW_FILE}"
  [ "$status" -eq 0 ]
}
