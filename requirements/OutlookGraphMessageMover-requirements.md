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
- R050-T01: Header defines `GraphRequestHeaders`/`MoveMessageRequest` typed structs consumed by `FetchGraphRequestData`/`MoveMessageToFolder` to avoid swappable-parameter SAST regressions.

R055  Statement: Resolve destination mail-folder ids by case-insensitive display-name lookup.
Design: `FindMailFolderIdByName` fetches `/me/mailFolders`, iterates folder rows, and returns the `id` for the first `displayName` matching the requested name case-insensitively.
Tests:
- R055-T01: Folder-id resolver fetches `/me/mailFolders` and matches `displayName` using case-insensitive comparison.

R060  Statement: Ensure destination folders exist by creating them when lookup misses.
Design: `EnsureMailFolderId` reuses `FindMailFolderIdByName`, and when missing, POSTs `{displayName}` to `/me/mailFolders` and returns the created folder id.
Tests:
- R060-T01: Folder ensure flow reuses lookup and creates `/me/mailFolders` entries when the destination folder is missing.

## Changelog

- 2026-06-05: Extracted from the monolithic Bridge requirements doc; owns the typed request structs and folder-move
  POST flow (R050).
- 2026-06-06: Added R055/R060 for folder-id lookup and ensure/create flow before move operations.
