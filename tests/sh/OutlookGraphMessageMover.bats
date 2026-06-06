#!/usr/bin/env bats

load helpers/repo_root

setup() {
  #R050: Test harness setup for OutlookGraphMessageMover contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  MOVER_H="${REPO_ROOT}/macos_app/Bridge/OutlookGraphMessageMover.h"
  MOVER_MM="${REPO_ROOT}/macos_app/Bridge/OutlookGraphMessageMover.mm"
}

@test "R050: mover keeps clang-tidy swappable-parameter-safe typed request structs" {
  #R050-T01: Header defines GraphRequestHeaders/MoveMessageRequest typed structs consumed by FetchGraphRequestData/MoveMessageToFolder to avoid swappable-parameter SAST regressions.
  run rg -F "struct GraphRequestHeaders" "${MOVER_H}"
  [ "$status" -eq 0 ]
  run rg -F "NSData *FetchGraphRequestData(" "${MOVER_MM}"
  [ "$status" -eq 0 ]
  run rg -F "const GraphRequestHeaders &headers" "${MOVER_MM}"
  [ "$status" -eq 0 ]
  run rg -F "struct MoveMessageRequest" "${MOVER_H}"
  [ "$status" -eq 0 ]
  run rg -F "BOOL MoveMessageToFolder(const MoveMessageRequest &request)" "${MOVER_MM}"
  [ "$status" -eq 0 ]
}

@test "R055: folder lookup resolves ids via case-insensitive display-name matching" {
  #R055-T01: Folder-id resolver fetches /me/mailFolders and matches displayName using case-insensitive comparison.
  run rg -F "NSString *FindMailFolderIdByName(NSString *folder_name)" "${MOVER_MM}"
  [ "$status" -eq 0 ]
  run rg -F '?$select=id,displayName' "${MOVER_MM}"
  [ "$status" -eq 0 ]
  run rg -F "caseInsensitiveCompare:folder_name] == NSOrderedSame" "${MOVER_MM}"
  [ "$status" -eq 0 ]
}

@test "R060: folder ensure flow creates destination folder when missing" {
  #R060-T01: Folder ensure flow reuses lookup and creates /me/mailFolders entries when the destination folder is missing.
  run rg -F "NSString *EnsureMailFolderId(NSString *folder_name)" "${MOVER_MM}"
  [ "$status" -eq 0 ]
  run rg -F "FindMailFolderIdByName(folder_name)" "${MOVER_MM}"
  [ "$status" -eq 0 ]
  run rg -F "https://graph.microsoft.com/v1.0/me/mailFolders" "${MOVER_MM}"
  [ "$status" -eq 0 ]
  run rg -F '@"displayName" : folder_name' "${MOVER_MM}"
  [ "$status" -eq 0 ]
}
