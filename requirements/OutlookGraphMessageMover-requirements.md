# Outlook Graph Message Mover Requirements

## Scope

Applies to the Graph folder-ensure and message-move client in `macos_app/Bridge/OutlookGraphMessageMover.h` and
`macos_app/Bridge/OutlookGraphMessageMover.mm`. This unit owns the authenticated POST transport, the typed request
value structs, and the move-to-folder flow.

R050  Statement: Keep bridge helper signatures compatible with blocking clang-tidy policy in `make sast`.
Design: Move/folder helpers avoid swappable-parameter signatures by grouping related request values into typed helper
structs (`GraphRequestHeaders`, `MoveMessageRequest`) and passing those structs to helper functions instead of adjacent
`NSString *` parameters. `FetchGraphRequestData` consumes a `GraphRequestHeaders`, and `MoveMessageToFolder` consumes a
`MoveMessageRequest`.
Tests:
- Verify `OutlookGraphMessageMover.h` defines `GraphRequestHeaders` and `OutlookGraphMessageMover.mm` uses it in
  `FetchGraphRequestData`.
- Verify `OutlookGraphMessageMover.h` defines `MoveMessageRequest` and `OutlookGraphMessageMover.mm` uses it in
  `MoveMessageToFolder`.

## Changelog

- 2026-06-05: Extracted from the monolithic Bridge requirements doc; owns the typed request structs and folder-move
  POST flow (R050).
