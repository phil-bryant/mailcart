# Bridge Requirements

## Scope

Applies to `macos_app/Bridge/OutlookClientBridge.h`, `macos_app/Bridge/OutlookClientBridge.mm`, `macos_app/Bridge/OutlookBridgeModels.h`, and `macos_app/Bridge/OutlookBridgeModels.m`.

R001  Statement: Expose Objective-C bridge operations for mailcart search and message read.
Design: `OutlookClientBridge` declares `searchMailcartsWithQuery:limit:` returning summary DTOs and `readMailcartWithMessageId:` returning a full mailcart DTO for Swift UI consumption.
Tests:
- Compile Objective-C/Swift interoperability and verify both bridge methods resolve with expected signatures.
- Attempt to call a missing method variant and verify compilation fails.

R005  Statement: Provide immutable Objective-C DTO models for mailcart summary and full mailcart payloads.
Design: `OutlookMailcartSummaryDTO` and `OutlookMailcartDTO` expose readonly copied `NSString` properties and disallow default initialization via `init NS_UNAVAILABLE`.
Tests:
- Instantiate DTOs through designated initializers and verify all properties retain expected values.
- Attempt `[OutlookMailcartDTO new]` or `[OutlookMailcartSummaryDTO init]` and verify compile-time unavailability.

R010  Statement: Normalize string conversion between Foundation and C++ payloads.
Design: Bridge helper conversions translate `std::string` to UTF-8 `NSString` and `NSString` to `std::string`, using an empty string result when UTF-8 extraction is null.
Tests:
- Pass ASCII and UTF-8 values through both conversion directions and verify semantic equivalence.
- Provide a string value that yields null UTF-8 extraction and verify empty C++ string fallback.

R015  Statement: Resolve live Graph payloads through runtime token-aware gateway behavior.
Design: Bridge gateway resolves `OUTLOOK_GRAPH_TOKEN` from runtime environment; when present it requests Graph `/me/messages` payloads and supplies parser-ready JSON, and when absent it returns deterministic empty payloads.
Tests:
- Run with token unset and verify search/read produce deterministic empty-value responses.
- Run with token set and verify Graph fetch payloads are handed to parser.

R020  Statement: Perform case-insensitive search matching over subject and preview fields.
Design: Search gateway logic normalizes subject/preview/query text and includes entries when query is empty or found in either field.
Tests:
- Query with varied letter case and verify equivalent result sets.
- Query with empty text and verify all fetched messages are eligible before limit trimming.

R025  Statement: Enforce non-negative and capped search result limits.
Design: Search gateway coerces negative limits to zero and returns at most the requested number of matched summaries.
Tests:
- Search with a negative limit and verify zero results.
- Search with a positive limit below available matches and verify result truncation to that exact count.

R030  Statement: Return summary-only payload fields in search responses.
Design: Search gateway serializes filtered Graph results using only `id`, `subject`, and `preview` fields before parser conversion into summary DTOs.
Tests:
- Execute a search and verify each summary result includes message id, subject, and preview values.
- Verify search summary mapping omits body/sender/recipient fields at parser stage.

R035  Statement: Resolve message read requests by id with empty-field fallback for unknown ids.
Design: Message gateway requests Graph message-by-id payloads and falls back to deterministic requested-id + empty-field shape when fetch/parse/token conditions are not satisfied.
Tests:
- Read a known Graph id and verify DTO field mapping from Graph message payload.
- Read an unknown/unavailable id and verify returned message preserves requested id with empty values for other fields.

R040  Statement: Instantiate and own C++ Outlook client dependencies inside bridge lifecycle.
Design: Bridge initialization constructs a single `OutlookClient` with bridge gateway/parser implementations and retains it through a `std::unique_ptr`.
Tests:
- Create bridge instance and verify search/read calls succeed without external dependency injection.
- Destroy bridge instances repeatedly and verify no lifecycle crashes occur.

R045  Statement: Convert C++ domain search/read results into Objective-C DTO arrays and objects.
Design: Search iterates domain summaries into mutable Objective-C array then returns immutable copy; read maps domain mailcart fields into `OutlookMailcartDTO` initialization.
Tests:
- Verify `searchMailcartsWithQuery:limit:` returns `NSArray<OutlookMailcartSummaryDTO *>` with expected element values.
- Verify `readMailcartWithMessageId:` returns an `OutlookMailcartDTO` whose properties match C++ domain output.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `macos_app/Bridge/*`.
- 2026-05-07: Updated bridge requirements for runtime Graph token flow and live message fetch behavior.
