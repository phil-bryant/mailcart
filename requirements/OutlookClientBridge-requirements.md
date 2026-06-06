# Outlook Client Bridge Requirements

## Scope

Applies to the core Objective-C++ bridge in `macos_app/Bridge/OutlookClientBridge.h` and `macos_app/Bridge/OutlookClientBridge.mm`.
This unit owns the public bridge surface, the gateway adapter, and the C++ client lifecycle. Graph HTTP fetching,
JSON conversion, payload parsing, and folder/move behavior live in their own sibling units and requirements docs.

R001  Statement: Expose Objective-C bridge operations for mailcart search and message read.
Design: `OutlookClientBridge` declares `searchMailcartsWithQuery:limit:cursor:` returning summary DTOs and
`readMailcartWithMessageId:` returning a full mailcart DTO; a `BridgeOutlookGateway` adapter implements
`FetchSearchPayload`/`FetchMessagePayload` by delegating to the Graph HTTP client unit.
Tests:
- Compile Objective-C/Swift interoperability and verify both bridge methods resolve with expected signatures.
- Verify the gateway exposes `FetchSearchPayload`/`FetchMessagePayload` overrides backed by the Graph client.

R040  Statement: Instantiate and own C++ Outlook client dependencies inside bridge lifecycle.
Design: Bridge initialization constructs a single `OutlookClient` with bridge gateway/parser implementations and
retains it through a `std::unique_ptr`.
Tests:
- Create bridge instance and verify search/read calls succeed without external dependency injection.
- Destroy bridge instances repeatedly and verify no lifecycle crashes occur.

R045  Statement: Convert C++ domain search/read results into Objective-C DTO arrays and objects.
Design: Search iterates domain summaries into a mutable Objective-C array then returns an immutable copy; read maps
domain mailcart fields into `OutlookMailcartDTO` initialization.
Tests:
- Verify `searchMailcartsWithQuery:limit:cursor:` returns `NSArray<OutlookMailcartSummaryDTO *>` with expected values.
- Verify `readMailcartWithMessageId:` returns an `OutlookMailcartDTO` whose properties match C++ domain output.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `macos_app/Bridge/*`.
- 2026-06-05: Split monolithic Bridge requirements into per-unit docs; this doc now scopes only the core bridge
  (R001/R040/R045). String conversion (R010), Graph HTTP (R015/R020/R025/R030), folder-move (R050), payload parsing
  (R035), and DTO models (R005) moved to their own units.
