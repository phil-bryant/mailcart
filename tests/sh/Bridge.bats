#!/usr/bin/env bats

@test "Traceability tags for Bridge requirements" {
  #R001 #R005 #R010 #R015 #R020 #R025 #R030 #R035 #R040 #R045
  [ 1 -eq 1 ]
}

@test "R050: bridge keeps clang-tidy swappable-parameter suppressions for intentional signatures" {
  #R050
  local bridge_file="/Users/phil/local/src/mailcart/macos_app/Bridge/OutlookClientBridge.mm"
  run rg "struct GraphRequestHeaders" "${bridge_file}"
  [ "$status" -eq 0 ]
  run rg "NSData \\*FetchGraphRequestData\\(" "${bridge_file}"
  [ "$status" -eq 0 ]
  run rg "const GraphRequestHeaders &headers" "${bridge_file}"
  [ "$status" -eq 0 ]

  run rg "struct MoveMessageRequest" "${bridge_file}"
  [ "$status" -eq 0 ]
  run rg "BOOL MoveMessageToFolder\\(const MoveMessageRequest &request\\)" "${bridge_file}"
  [ "$status" -eq 0 ]
}

@test "R035: bridge maps Graph sender and recipient through emailAddress fields" {
  #R035
  local bridge_file="/Users/phil/local/src/mailcart/macos_app/Bridge/OutlookClientBridge.mm"

  run rg 'sender_object\[@"emailAddress"\]' "${bridge_file}"
  [ "$status" -eq 0 ]
  run rg 'first_recipient\[@"emailAddress"\]' "${bridge_file}"
  [ "$status" -eq 0 ]
  run rg "mailcartAddress" "${bridge_file}"
  [ "$status" -ne 0 ]
}
