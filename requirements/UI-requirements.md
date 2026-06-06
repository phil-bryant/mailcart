# UI Requirements

## Scope

Applies to `macos_app/UI/OutlookMailApp.swift`, `macos_app/UI/OutlookMailContentView.swift`, and `macos_app/UI/OutlookMailViewModel.swift`.

R001  Statement: Launch the macOS Outlook mail experience from a SwiftUI app entrypoint.
Design: `OutlookMailApp` defines the `@main` app scene as a single `WindowGroup` rooted at `OutlookMailContentView`.
Tests:
- R001-T01: `OutlookMailApp` is the `@main` app exposing a single `WindowGroup` rooted at `OutlookMailContentView`.

R005  Statement: Enforce minimum desktop window size suitable for split-mail workflow.
Design: Root content view applies frame constraints of at least 980 width and 620 height.
Tests:
- R005-T01: Root content applies a minimum window frame of 980 width and 620 height.

R010  Statement: Present mailbox and message content using split navigation layout.
Design: `OutlookMailContentView` uses `NavigationSplitView` with list/search in the primary column and selected message detail in the secondary column.
Tests:
- R010-T01: `OutlookMailContentView` uses `NavigationSplitView` with the `Outlook` primary navigation title.

R015  Statement: Bind search field edits to view-model query updates.
Design: Search text field displays `Search Outlook mail` placeholder and uses explicit binding that delegates writes through `viewModel.updateQuery(_:)`.
Tests:
- R015-T01: The `Search Outlook mail` field delegates writes through `viewModel.updateQuery(_:)`.

R020  Statement: Surface active search progress in the mailbox column.
Design: UI conditionally renders `ProgressView("Searching…")` while `viewModel.isSearching` is true.
Tests:
- R020-T01: A `Searching…` `ProgressView` renders while `viewModel.isSearching` is true.

R025  Statement: Render searchable summary results with selectable message identity.
Design: Primary list binds to `viewModel.summaries`, identifies rows by `messageId`, and tags each row with the same id for selection tracking.
Tests:
- R025-T01: The summary list keys on `viewModel.summaries` `messageId` and tags each row by id.

R030  Statement: Display subject and preview hierarchy in summary rows.
Design: Each summary row shows headline one-line subject and two-line secondary preview styling for scan-friendly mailbox display.
Tests:
- R030-T01: Summary rows show a one-line subject headline and a two-line secondary preview.

R035  Statement: Load full mailcart content when a non-empty message selection changes.
Design: Selection change handler maps optional selected id to string and invokes `viewModel.loadMailcart(messageId:)` only when id is non-empty.
Tests:
- R035-T01: A non-empty selection change invokes `viewModel.loadMailcart(messageId:)`.

R040  Statement: Render selected mailcart details with readable metadata and body content.
Design: Detail pane shows subject title plus From/To/Received metadata, divider, and full message body content where rendered mode uses the HTML renderer component for HTML payloads while plain-text payloads remain selectable SwiftUI text.
Tests:
- R040-T01: Detail pane renders subject, From/To/Received metadata, and a selection-enabled body.

R045  Statement: Render an empty-state prompt when no mailcart is selected.
Design: Detail pane displays envelope icon, bold `Select an mailcart` heading, and explanatory guidance while `selectedMailcart` is nil.
Tests:
- R045-T01: With no selection the detail pane shows the `envelope.open` empty-state prompt.

R050  Statement: Maintain main-actor observable UI state for query, summaries, selected mailcart, and search status.
Design: `OutlookMailViewModel` is `@MainActor` and publishes mutable `query` plus private-set `summaries`, `selectedMailcart`, `isSearching`, and `errorMessage`.
Tests:
- R050-T01: `OutlookMailViewModel` is a `@MainActor` observable with private-set published state.

R055  Statement: Debounce and cancel superseded search requests.
Design: `scheduleSearch()` cancels prior task, marks searching active, waits 250ms, exits cancelled tasks early, then performs bridge search with `limit: 50`.
Tests:
- R055-T01: `scheduleSearch` cancels prior tasks, waits 250ms, and searches with `limit: 50`.

R060  Statement: Map bridge read/search responses into published UI state.
Design: `loadMailcart(messageId:)` schedules asynchronous bridge read work and updates `selectedMailcart` when the latest in-flight request completes; completed debounced search assigns returned summaries then clears searching flag.
Tests:
- R060-T01: Bridge read/search work runs off the main actor and maps results into published UI state.

R065  Statement: Load initial mailbox content automatically when the UI launches.
Design: `OutlookMailViewModel` schedules an initial search from `init` without requiring search-field input.
Tests:
- R065-T01: The view-model `init` schedules an initial mailbox load via `scheduleSearch(isInitialLoad: true)`.

R070  Statement: Allow users to request additional server-paginated mailcart summaries.
Design: View-model tracks `nextCursor` from bridge search results, exposes `canLoadMore`, and appends summaries when `Load more emails` is clicked.
Tests:
- R070-T01: A cursor-backed `Load more emails` action appends summaries when `canLoadMore` is true.

R075  Statement: Provide rendered-vs-raw mailcart body mode with rendered as default.
Design: Detail pane exposes segmented body mode control defaulted to `Rendered`, showing HTML content via `HTMLBodyView` in rendered mode and raw source in raw mode.
Tests:
- R075-T01: Detail body mode defaults to rendered `HTMLBodyView` with a raw-source toggle.

R080  Statement: Display and open all attachments for the selected mailcart.
Design: Detail pane lists attachment metadata and routes each `Open` action through view-model bridge attachment open API.
Tests:
- R080-T01: Detail lists attachment metadata and routes each `Open` action through the bridge.

R085  Statement: Support mailbox sorting by subject or received date.
Design: Mailbox column exposes segmented sort control and view-model sorts summary list by selected key (`Subject` ascending, `Date received` descending).
Tests:
- R085-T01: Mailbox sorting orders by subject ascending or received date descending.

R090  Statement: Terminate the app when the user closes the main window.
Design: App entrypoint configures `NSApplicationDelegate` to return true from `applicationShouldTerminateAfterLastWindowClosed`.
Tests:
- R090-T01: The app delegate terminates the process after the last window closes.

R095  Statement: Surface actionable mailbox error messaging in the UI.
Design: View-model sets `errorMessage` when token/bootstrap conditions prevent mailbox loading and content view renders the message inline in the mailbox column.
Tests:
- R095-T01: The view-model surfaces an actionable mailbox `errorMessage` rendered inline in the UI.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `macos_app/UI/*`.
- 2026-05-07: Added requirements for initial load, pagination, body mode toggle, attachments, sorting, close-to-terminate lifecycle, and mailbox error messaging.
- 2026-05-13: Tightened regression requirements for async non-blocking detail loads, HTML renderer usage, and updated load-more button copy.
