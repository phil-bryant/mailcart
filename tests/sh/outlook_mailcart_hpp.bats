#!/usr/bin/env bats

# Interface contract checks for the cpp_core OutlookMailcart header. The compiled
# behavior is exercised by the C++ integration lane; these checks assert the
# header declares the interface each requirement depends on.

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  HDR="${REPO_ROOT}/cpp_core/include/outlook_mailcart.hpp"
}

@test "R001: header declares JSON wrapper, attachment type, and OutlookMailcart entity" {
  #R001-T01: Verify the header declares the JSON object wrapper, attachment type, and the OutlookMailcart entity with its accessors and type() override.
  run rg -F "void SetStringField(std::string key, std::string value);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] bool hasField(const std::string &key) const;" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] std::string stringFieldOrDefault(const std::string &key, std::string_view default_value) const;" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "OutlookAttachment(std::string attachment_id, std::string file_name, std::string content_type, int size_in_bytes);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "class OutlookMailcart : public Mailcart" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "explicit OutlookMailcart(const OutlookJsonObject &json_object) noexcept(false);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] const std::string &messageId() const;" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] std::string type() const override;" "${HDR}"
  [ "$status" -eq 0 ]
}
