import SwiftUI

// #R001: Participate in app entrypoint flow by hosting mailbox content.
// #R005: Respect minimum window-size contract inherited from app scene.
// #R010: Present mailbox and message content with split navigation layout.
// #R015: Bind search field edits to view-model query updates.
// #R020: Surface active search progress while search task runs.
// #R025: Render selectable summary list keyed by message id.
// #R030: Display subject/preview hierarchy in mailbox rows.
// #R035: Load full mailcart content when non-empty selection changes.
// #R040: Render selected mailcart detail metadata and body content.
// #R045: Render empty-state prompt when no message is selected.
// #R050: Consume main-actor observable UI state from view model.
// #R055: Reflect debounced/cancelled searches through searching state.
// #R060: Display bridge read/search responses from published state.
// #R065: Render mailbox with immediate startup loading behavior.
// #R070: Provide user control to request additional paged mailcarts.
// #R075: Provide rendered-vs-raw body mode toggle defaulting to rendered.
// #R080: Render all message attachments and open actions.
// #R085: Expose sort controls for subject/date received ordering.
// #R090: Respect app lifecycle close behavior from app delegate.
// #R095: Display mailbox error messaging inline.
struct OutlookMailContentView: View {
    private enum BodyDisplayMode: String, CaseIterable, Identifiable {
        case rendered = "Rendered"
        case raw = "Raw"

        var id: String {
            rawValue
        }
    }

    @StateObject private var viewModel = OutlookMailViewModel()
    @State private var selectedMessageId: String?
    @State private var bodyDisplayMode: BodyDisplayMode = .rendered

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search Outlook mail", text: Binding(
                    get: { viewModel.query },
                    set: { value in viewModel.updateQuery(value) }
                ))
                .accessibilityIdentifier("mailcart.searchField")
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // #R085: User-selectable subject/date sort mode.
                Picker("Sort", selection: Binding(
                    get: { viewModel.sortOption },
                    set: { value in viewModel.updateSortOption(value) }
                )) {
                    ForEach(OutlookMailViewModel.MailSortOption.allCases, id: \.self) { option in
                        Text(option.rawValue)
                            .tag(option)
                            .accessibilityIdentifier(option == .subject ? "mailcart.sortSubject" : "mailcart.sortDate")
                    }
                }
                .accessibilityIdentifier("mailcart.sortMode")
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)

                if viewModel.isSearching {
                    ProgressView("Searching…")
                        .padding(.horizontal, 12)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                }

                List(viewModel.summaries, id: \.messageId, selection: $selectedMessageId) { summary in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.subject)
                            .font(.headline)
                            .lineLimit(1)
                            .accessibilityIdentifier("mailcart.summarySubject.\(summary.messageId)")
                        Text(summary.preview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(summary.receivedAt)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .tag(summary.messageId)
                }
                .accessibilityIdentifier("mailcart.summaryList")

                // #R070: Explicit load-more action fetches next page from bridge cursor.
                Button(action: {
                    viewModel.loadMoreMailcarts()
                }, label: {
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Load more emails")
                    }
                })
                .accessibilityIdentifier("mailcart.loadMoreButton")
                .disabled(viewModel.canLoadMore == false)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .navigationTitle("Outlook")
            .onChange(of: selectedMessageId) { newValue in
                let messageId = newValue ?? ""
                if messageId.isEmpty == false {
                    viewModel.loadMailcart(messageId: messageId)
                    bodyDisplayMode = .rendered
                }
            }
        } detail: {
            if let mailcart = viewModel.selectedMailcart {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(mailcart.subject)
                            .font(.title2)
                            .bold()
                            .accessibilityIdentifier("mailcart.detailSubject")
                        Text("From: \(mailcart.sender)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("mailcart.detailSender")
                        Text("To: \(mailcart.recipient)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("mailcart.detailRecipient")
                        Text("Received: \(mailcart.receivedAt)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 6)
                        // #R075: Rendered mode is default with explicit raw toggle.
                        Picker("Body", selection: $bodyDisplayMode) {
                            ForEach(BodyDisplayMode.allCases) { mode in
                                Text(mode.rawValue)
                                    .tag(mode)
                                    // swiftlint:disable:next line_length
                                    .accessibilityIdentifier(mode == .rendered ? "mailcart.bodyModeRendered" : "mailcart.bodyModeRaw")
                            }
                        }
                        .accessibilityIdentifier("mailcart.bodyMode")
                        .pickerStyle(.segmented)
                        Divider()
                        if bodyDisplayMode == .rendered {
                            renderedBodyView(mailcart: mailcart)
                        } else {
                            rawBodyView(mailcart: mailcart)
                        }
                        // #R080: Show all attachment metadata and open actions.
                        if mailcart.attachments.isEmpty == false {
                            Divider()
                            Text("Attachments")
                                .font(.headline)
                            ForEach(mailcart.attachments, id: \.attachmentId) { attachment in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(attachment.fileName)
                                        Text("\(attachment.contentType) • \(attachment.sizeInBytes) bytes")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Open") {
                                        viewModel.openAttachment(attachment)
                                    }
                                    .accessibilityIdentifier("mailcart.openAttachment.\(attachment.attachmentId)")
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "envelope.open")
                        .font(.largeTitle)
                    Text("Select an email")
                        .font(.title3)
                        .bold()
                    Text("Choose a message in the list to read it.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func renderedBodyView(mailcart: OutlookMailcartDTO) -> some View {
        let htmlBody = mailcart.bodyHtml
        if htmlBody.isEmpty == false {
            HTMLBodyView(html: htmlBody)
                .frame(minHeight: 420)
                .accessibilityIdentifier("mailcart.renderedBody")
        } else {
            Text(mailcart.bodyText.isEmpty ? mailcart.body : mailcart.bodyText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("mailcart.renderedFallbackBody")
        }
    }

    private func rawBodyView(mailcart: OutlookMailcartDTO) -> some View {
        let rawBody = mailcart.bodyHtml.isEmpty ? mailcart.bodyText : mailcart.bodyHtml
        return Text(rawBody)
            .font(.body.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("mailcart.rawBodyText")
    }

}
