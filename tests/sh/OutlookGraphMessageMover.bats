#!/usr/bin/env bats

load helpers/repo_root

setup() {
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
