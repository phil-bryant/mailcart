# UI Requirements

## Scope

Applies to `macos_app/UI/OutlookMailApp.swift`, `macos_app/UI/OutlookMailContentView.swift`, and `macos_app/UI/OutlookMailViewModel.swift`.

R001  Statement: Launch the macOS Outlook mail experience from a SwiftUI app entrypoint.
Design: `OutlookMailApp` defines the `@main` app scene as a single `WindowGroup` rooted at `OutlookMailContentView`.
Tests:
- Build and launch the macOS target and verify `OutlookMailContentView` is the initial window content.
- Verify app startup does not require manual scene wiring outside `OutlookMailApp`.

R005  Statement: Enforce minimum desktop window size suitable for split-mail workflow.
Design: Root content view applies frame constraints of at least 980 width and 620 height.
Tests:
- Launch app and attempt to resize below minimum dimensions; verify minimum size is enforced.
- Verify initial window opens at or above configured minimum frame.

R010  Statement: Present mailbox and message content using split navigation layout.
Design: `OutlookMailContentView` uses `NavigationSplitView` with list/search in the primary column and selected message detail in the secondary column.
Tests:
- Launch app and verify both list and detail regions render within split navigation.
- Verify navigation title displays `Outlook` on the primary column.

R015  Statement: Bind search field edits to view-model query updates.
Design: Search text field displays `Search Outlook mail` placeholder and uses explicit binding that delegates writes through `viewModel.updateQuery(_:)`.
Tests:
- Type into search field and verify `updateQuery(_:)` is invoked with current text.
- Clear search field text and verify query state updates to empty string.

R020  Statement: Surface active search progress in the mailbox column.
Design: UI conditionally renders `ProgressView("Searching…")` while `viewModel.isSearching` is true.
Tests:
- Trigger a query update and verify progress indicator appears during active search task window.
- Verify progress indicator hides after summaries update and search completes.

R025  Statement: Render searchable summary results with selectable message identity.
Design: Primary list binds to `viewModel.summaries`, identifies rows by `messageId`, and tags each row with the same id for selection tracking.
Tests:
- Populate summaries and verify list row count matches summary count.
- Select a row and verify selected id tracks the row `messageId`.

R030  Statement: Display subject and preview hierarchy in summary rows.
Design: Each summary row shows headline one-line subject and two-line secondary preview styling for scan-friendly mailbox display.
Tests:
- Provide long subject/preview values and verify one-line and two-line truncation behavior.
- Verify preview text uses secondary foreground styling distinct from subject.

R035  Statement: Load full mailcart content when a non-empty message selection changes.
Design: Selection change handler maps optional selected id to string and invokes `viewModel.loadMailcart(messageId:)` only when id is non-empty.
Tests:
- Select a valid message id and verify detail load is requested for that id.
- Clear selection and verify no load call occurs for empty id.

R040  Statement: Render selected mailcart details with readable metadata and body content.
Design: Detail pane shows subject title plus From/To/Received metadata, divider, and full message body text with selection enabled.
Tests:
- Load a message and verify subject, sender, recipient, timestamp, and body all render.
- Verify body text supports text selection interaction.

R045  Statement: Render an empty-state prompt when no mailcart is selected.
Design: Detail pane displays envelope icon, bold `Select an mailcart` heading, and explanatory guidance while `selectedMailcart` is nil.
Tests:
- Launch app before any selection and verify empty-state icon and messaging are visible.
- Deselect current message and verify detail pane returns to empty-state content.

R050  Statement: Maintain main-actor observable UI state for query, summaries, selected mailcart, and search status.
Design: `OutlookMailViewModel` is `@MainActor` and publishes mutable `query` plus private-set `summaries`, `selectedMailcart`, `isSearching`, and `errorMessage`.
Tests:
- Observe published properties and verify state updates are delivered on main actor.
- Attempt external mutation of private-set properties and verify access is disallowed.

R055  Statement: Debounce and cancel superseded search requests.
Design: `scheduleSearch()` cancels prior task, marks searching active, waits 250ms, exits cancelled tasks early, then performs bridge search with `limit: 50`.
Tests:
- Enter text rapidly and verify only latest query produces final summaries.
- Confirm cancelled tasks do not overwrite summaries or searching state after cancellation.

R060  Statement: Map bridge read/search responses into published UI state.
Design: `loadMailcart(messageId:)` synchronously updates `selectedMailcart` from bridge read result, and completed debounced search assigns returned summaries then clears searching flag.
Tests:
- Invoke `loadMailcart(messageId:)` with known id and verify `selectedMailcart` updates to returned DTO.
- Complete a search and verify `summaries` updates and `isSearching` becomes false.

R065  Statement: Load initial mailbox content automatically when the UI launches.
Design: `OutlookMailViewModel` schedules an initial search from `init` without requiring search-field input.
Tests:
- Launch app and verify mailbox list populates from bridge-backed search without typing a query.
- Verify initial load still executes when query is empty.

R070  Statement: Allow users to request additional server-paginated mailcart summaries.
Design: View-model tracks `nextCursor` from bridge search results, exposes `canLoadMore`, and appends summaries when `Load more mailcarts` is clicked.
Tests:
- Perform a search with multi-page backend data and verify clicking `Load more mailcarts` appends additional rows.
- Verify load-more button disables when no continuation cursor is available.

R075  Statement: Provide rendered-vs-raw mailcart body mode with rendered as default.
Design: Detail pane exposes segmented body mode control defaulted to `Rendered`, showing rendered HTML/plain text in rendered mode and raw source in raw mode.
Tests:
- Select an mailcart with HTML body and verify default detail body is rendered mode.
- Switch to raw mode and verify raw source body text is shown.

R080  Statement: Display and open all attachments for the selected mailcart.
Design: Detail pane lists attachment metadata and routes each `Open` action through view-model bridge attachment open API.
Tests:
- Select an mailcart with attachments and verify list displays filename/type/size for every attachment.
- Trigger `Open` on an attachment and verify bridge open handler is invoked with selected message and attachment ids.

R085  Statement: Support mailbox sorting by subject or received date.
Design: Mailbox column exposes segmented sort control and view-model sorts summary list by selected key (`Subject` ascending, `Date received` descending).
Tests:
- Switch sort to subject and verify alphabetical subject ordering.
- Switch sort to date received and verify newest-first ordering.

R090  Statement: Terminate the app when the user closes the main window.
Design: App entrypoint configures `NSApplicationDelegate` to return true from `applicationShouldTerminateAfterLastWindowClosed`.
Tests:
- Launch app, close the window via red traffic-light button, and verify process exits.
- Verify app does not linger after window close when started from `make run`.

R095  Statement: Surface actionable mailbox error messaging in the UI.
Design: View-model sets `errorMessage` when token/bootstrap conditions prevent mailbox loading and content view renders the message inline in the mailbox column.
Tests:
- Launch without `OUTLOOK_GRAPH_TOKEN` and verify error message is visible.
- Restore token and verify successful searches clear the blocking error state.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `macos_app/UI/*`.
- 2026-05-07: Added requirements for initial load, pagination, body mode toggle, attachments, sorting, close-to-terminate lifecycle, and mailbox error messaging.
