#!/usr/bin/env bats

load helpers/repo_root

setup() {
  #R035: Test harness setup for OutlookBridgeParser contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  PARSER_MM="${REPO_ROOT}/macos_app/Bridge/OutlookBridgeParser.mm"
}

@test "R035: parser maps Graph sender and recipient through emailAddress fields" {
  #R035-T01: Message reads map sender/recipient via Graph emailAddress.address fields with empty-field fallback for unknown ids.
  run rg -F 'sender_object[@"emailAddress"]' "${PARSER_MM}"
  [ "$status" -eq 0 ]
  run rg -F 'first_recipient[@"emailAddress"]' "${PARSER_MM}"
  [ "$status" -eq 0 ]
  run rg -F 'sender_address[@"address"]' "${PARSER_MM}"
  [ "$status" -eq 0 ]
  run rg -F "mailcartAddress" "${PARSER_MM}"
  [ "$status" -ne 0 ]
}
