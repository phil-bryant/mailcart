#!/usr/bin/env bats

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  CONVERSIONS_MM="${REPO_ROOT}/macos_app/Bridge/OutlookGraphConversions.mm"
}

@test "R010: bridge string conversions bridge std::string<->NSString with null-safe fallback" {
  #R010-T01: ToNSString/ToStdString convert between std::string and NSString with null-safe empty-string fallbacks.
  run rg -F "NSString * _Nonnull ToNSString(const std::string &value)" "${CONVERSIONS_MM}"
  [ "$status" -eq 0 ]
  run rg -F "std::string ToStdString(NSString *value)" "${CONVERSIONS_MM}"
  [ "$status" -eq 0 ]
  run rg -F "if (result == nil)" "${CONVERSIONS_MM}"
  [ "$status" -eq 0 ]
  run rg -F "if (utf8_value != nullptr)" "${CONVERSIONS_MM}"
  [ "$status" -eq 0 ]
}
