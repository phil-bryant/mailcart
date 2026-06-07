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
- R001-T01: Bridge declares ObjC search/read entrypoints and the gateway exposes `FetchSearchPayload`/`FetchMessagePayload` backed by the Graph client.

R040  Statement: Instantiate and own C++ Outlook client dependencies inside bridge lifecycle.
Design: Bridge initialization constructs a single `OutlookClient` with bridge gateway/parser implementations and
retains it through a `std::unique_ptr`.
Tests:
- R040-T01: Bridge constructs and owns a single C++ `OutlookClient` through a `std::unique_ptr` lifecycle.

R045  Statement: Convert C++ domain search/read results into Objective-C DTO arrays and objects.
Design: Search iterates domain summaries into a mutable Objective-C array then returns an immutable copy; read maps
domain mailcart fields into `OutlookMailcartDTO` initialization.
Tests:
- R045-T01: Search maps C++ summaries into an immutable `NSArray<OutlookMailcartSummaryDTO *>` and read maps domain fields into an `OutlookMailcartDTO`.

R050  Statement: Expose and implement bridge attachment-open entrypoint flow.
Design: `openAttachmentWithMessageId:attachmentId:fileName:` resolves a Graph token, fetches attachment bytes from the
Graph `$value` endpoint, writes to a temporary file, and opens the file URL through `NSWorkspace`.
Tests:
- R050-T01: Bridge header declares the attachment-open selector and implementation stages fetched bytes to a temp path before opening with `NSWorkspace`.

R055  Statement: Expose and implement bridge folder-move entrypoint flow.
Design: `moveMessageToFolderWithMessageId:folderName:` trims folder input, defaults blank folder names to `matchy`, and
delegates the request via `MoveMessageToFolder`.
Tests:
- R055-T01: Bridge header declares the folder-move selector and implementation normalizes blank folder names before dispatching `MoveMessageToFolder`.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `macos_app/Bridge/*`.
- 2026-06-07: Added R050/R055 for attachment-open and folder-move bridge entrypoints so Objective-C selectors are directly traced in this unit.
- 2026-06-05: Split monolithic Bridge requirements into per-unit docs; this doc now scopes only the core bridge
  (R001/R040/R045). String conversion (R010), Graph HTTP (R015/R020/R025/R030), folder-move internals (R050), payload parsing
  (R035), and DTO models (R005) moved to their own units.
