import Foundation

protocol OutlookBridgeClient: AnyObject, Sendable {
    var isUITestingFixture: Bool { get }
    func searchMailcarts(withQuery query: String, limit: Int, cursor: String) -> OutlookSearchResultDTO
    func readMailcart(withMessageId messageId: String) -> OutlookMailcartDTO
    func openAttachment(withMessageId messageId: String, attachmentId: String, fileName: String) -> Bool
}

extension OutlookClientBridge: OutlookBridgeClient {
    var isUITestingFixture: Bool { false }
}

private struct FixtureMailcartRecord {
    let messageId: String
    let subject: String
    let preview: String
    let receivedAt: String
    let sender: String
    let recipient: String
    let bodyText: String
    let bodyHTML: String
    let attachments: [OutlookAttachmentDTO]
}

enum MailcartAppLaunchMode {
    case normal
    case uiTesting
}

// #R001: Launch mode detection selects the UI-testing fixture bridge via --ui-testing or MAILCART_UI_TEST_MODE.
func detectMailcartLaunchMode(processInfo: ProcessInfo = .processInfo) -> MailcartAppLaunchMode {
    if processInfo.arguments.contains("--ui-testing") || processInfo.environment["MAILCART_UI_TEST_MODE"] == "1" {
        return .uiTesting
    }
    return .normal
}

func buildDefaultOutlookBridgeClient(processInfo: ProcessInfo = .processInfo) -> OutlookBridgeClient {
    switch detectMailcartLaunchMode(processInfo: processInfo) {
    case .normal:
        return OutlookClientBridge()
    case .uiTesting:
        return UITestingFixtureBridge(processInfo: processInfo)
    }
}

// #R005: UITestingFixtureBridge serves deterministic in-memory mailcart fixtures with cursor pagination.
final class UITestingFixtureBridge: NSObject, OutlookBridgeClient, @unchecked Sendable {
    var isUITestingFixture: Bool { true }

    private let pageSize: Int
    private let records: [FixtureMailcartRecord]

    init(processInfo: ProcessInfo = .processInfo) {
        pageSize = Self.resolvedPageSize(processInfo)
        records = Self.fixtureRecords()
        super.init()
    }

    private static func resolvedPageSize(_ processInfo: ProcessInfo) -> Int {
        Int(processInfo.environment["MAILCART_UI_TEST_PAGE_SIZE"] ?? "2") ?? 2
    }

    private static func fixtureRecords() -> [FixtureMailcartRecord] {
        [
            fixtureRecord001(),
            fixtureRecord002(),
            fixtureRecord003(),
            fixtureRecord004()
        ]
    }

    private static func fixtureRecord001() -> FixtureMailcartRecord {
        FixtureMailcartRecord(
            messageId: "msg_001",
            subject: "Coffee Roasters weekly update",
            preview: "Your order receipt and points update are ready.",
            receivedAt: "2026-05-12T10:30:00Z",
            sender: "coffee@example.com",
            recipient: "user@example.com",
            bodyText: "Thanks for your coffee order.",
            bodyHTML: "<p>Thanks for your <strong>coffee</strong> order.</p>",
            attachments: [
                // swiftlint:disable:next line_length
                OutlookAttachmentDTO(attachmentId: "att_001", fileName: "receipt.pdf", contentType: "application/pdf", sizeInBytes: 12400)
            ]
        )
    }

    private static func fixtureRecord002() -> FixtureMailcartRecord {
        FixtureMailcartRecord(
            messageId: "msg_002",
            subject: "Electric Utility Co statement",
            preview: "Your monthly utility statement is available.",
            receivedAt: "2026-05-11T09:00:00Z",
            sender: "billing@utility.example.com",
            recipient: "user@example.com",
            bodyText: "Utility statement enclosed.",
            bodyHTML: "",
            attachments: []
        )
    }

    private static func fixtureRecord003() -> FixtureMailcartRecord {
        FixtureMailcartRecord(
            messageId: "msg_003",
            subject: "City Transit Card refill notice",
            preview: "Auto-refill will process tomorrow.",
            receivedAt: "2026-05-10T08:00:00Z",
            sender: "transit@example.com",
            recipient: "user@example.com",
            bodyText: "Your transit card auto-refill is scheduled.",
            bodyHTML: "<p>Your transit card <em>auto-refill</em> is scheduled.</p>",
            attachments: []
        )
    }

    private static func fixtureRecord004() -> FixtureMailcartRecord {
        FixtureMailcartRecord(
            messageId: "msg_004",
            subject: "Airline Luggage Fee confirmation",
            preview: "Additional baggage fee has been confirmed.",
            receivedAt: "2026-05-09T07:30:00Z",
            sender: "travel@example.com",
            recipient: "user@example.com",
            bodyText: "Baggage fee confirmation details attached.",
            bodyHTML: "",
            attachments: [
                // swiftlint:disable:next line_length
                OutlookAttachmentDTO(attachmentId: "att_002", fileName: "itinerary.txt", contentType: "text/plain", sizeInBytes: 740)
            ]
        )
    }

    func searchMailcarts(withQuery query: String, limit: Int, cursor: String) -> OutlookSearchResultDTO {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = records.filter { record in
            if normalizedQuery.isEmpty {
                return true
            }
            return record.subject.lowercased().contains(normalizedQuery)
                || record.preview.lowercased().contains(normalizedQuery)
                || record.messageId.lowercased().contains(normalizedQuery)
        }
        let offset = Int(cursor) ?? 0
        let safeOffset = max(0, min(offset, filtered.count))
        let effectiveLimit = min(max(limit, 1), max(pageSize, 1))
        let upperBound = min(filtered.count, safeOffset + effectiveLimit)
        let page = Array(filtered[safeOffset..<upperBound])
        let summaries = page.map {
            // swiftlint:disable:next line_length
            OutlookMailcartSummaryDTO(messageId: $0.messageId, subject: $0.subject, preview: $0.preview, receivedAt: $0.receivedAt)
        }
        let nextCursor = upperBound < filtered.count ? String(upperBound) : ""
        return OutlookSearchResultDTO(summaries: summaries, nextCursor: nextCursor, errorMessage: "")
    }

    func readMailcart(withMessageId messageId: String) -> OutlookMailcartDTO {
        let fallback = records.first ?? FixtureMailcartRecord(
            messageId: messageId,
            subject: "Unknown fixture message",
            preview: "",
            receivedAt: "",
            sender: "",
            recipient: "",
            bodyText: "",
            bodyHTML: "",
            attachments: []
        )
        let record = records.first(where: { $0.messageId == messageId }) ?? fallback
        return OutlookMailcartDTO(
            messageId: record.messageId,
            sender: record.sender,
            recipient: record.recipient,
            subject: record.subject,
            receivedAt: record.receivedAt,
            body: record.bodyText.isEmpty ? record.bodyHTML : record.bodyText,
            bodyText: record.bodyText,
            bodyHtml: record.bodyHTML,
            attachments: record.attachments
        )
    }

    func openAttachment(withMessageId messageId: String, attachmentId: String, fileName: String) -> Bool {
        records.contains { $0.messageId == messageId && $0.attachments.contains { $0.attachmentId == attachmentId } }
    }
}
