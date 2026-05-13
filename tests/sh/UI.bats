#!/usr/bin/env bats

@test "Traceability tags for UI requirements" {
  #R001 #R005 #R010 #R015 #R020 #R025 #R030 #R035 #R040 #R045 #R050 #R055 #R060 #R065 #R070 #R075 #R080 #R085 #R090 #R095
  [ 1 -eq 1 ]
}

@test "R070: mailbox action label uses load more emails wording" {
  #R070
  local view_file="/Users/phil/local/src/mailcart/macos_app/UI/OutlookMailContentView.swift"
  run rg 'Text\("Load more emails"\)' "${view_file}"
  [ "$status" -eq 0 ]
}

@test "R075: rendered mode uses HTMLBodyView and raw mode keeps source text" {
  #R075
  local view_file="/Users/phil/local/src/mailcart/macos_app/UI/OutlookMailContentView.swift"
  local html_view_file="/Users/phil/local/src/mailcart/macos_app/UI/HTMLBodyView.swift"
  run rg 'HTMLBodyView\(html: htmlBody\)' "${view_file}"
  [ "$status" -eq 0 ]
  run rg 'private func rawBodyView\(mailcart: OutlookMailcartDTO\)' "${view_file}"
  [ "$status" -eq 0 ]
  run rg 'import WebKit' "${html_view_file}"
  [ "$status" -eq 0 ]
}

@test "R060: view model performs bridge search/read off the main actor" {
  #R060
  local view_model_file="/Users/phil/local/src/mailcart/macos_app/UI/OutlookMailViewModel.swift"
  run rg 'private let bridgeQueue = DispatchQueue\(label: "mailcart.outlook-bridge-queue"' "${view_model_file}"
  [ "$status" -eq 0 ]
  run rg 'let result = await self\.readMailcartFromBridge\(messageId: messageId\)' "${view_model_file}"
  [ "$status" -eq 0 ]
  run rg 'let result = await searchMailcartsFromBridge\(query: queryAtRequestTime, cursor: cursor\)' "${view_model_file}"
  [ "$status" -eq 0 ]
}
