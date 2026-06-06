#!/usr/bin/env bats

# Behavioral contract checks for the cpp_core OutlookMailcart entity. Compiled
# behavior is exercised by the C++ integration lane
# (tests/t08_run_cpp_integration_tests.sh); these checks assert the source
# implements each requirement's design contract so regressions fail the lane.

load helpers/repo_root

setup() {
  #R001: Test harness setup for outlook_mailcart contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/cpp_core/src/outlook_mailcart.cpp"
}

@test "R001: MIME body builder prefers plain text over HTML" {
  #R001-T01: MIME body builder prefers plain text when bodyText is present, else HTML when bodyHtml is present.
  run rg -F 'std::string text_body = json_object.stringFieldOrDefault("bodyText", "");' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "if (!text_body.empty())" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "mime_content = MimeContent::PlainText(std::move(text_body));" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "mime_content = MimeContent::Html(std::move(html_body));" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: absent body fields fall back to empty application/unknown MIME" {
  #R005-T01: Absent or empty body fields fall back to an empty application/unknown MIME payload.
  run rg -F 'MimeContent mime_content("application/unknown", "");' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R010: SetStringField stores key/value pairs in the field map" {
  #R010-T01: SetStringField stores key/value pairs in the internal field map.
  run rg -F "void OutlookJsonObject::SetStringField(std::string key, std::string value)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "string_fields_[std::move(key)] = std::move(value);" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R015: hasField reports presence by exact key membership" {
  #R015-T01: hasField reports field presence by exact key membership.
  run rg -F "bool OutlookJsonObject::hasField(const std::string &key) const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "if (string_fields_.find(key) != string_fields_.end())" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R020: stringFieldOrDefault returns the caller default for missing keys" {
  #R020-T01: stringFieldOrDefault returns the stored value for present keys and the caller default otherwise.
  run rg -F "std::string OutlookJsonObject::stringFieldOrDefault(const std::string &key, std::string_view default_value) const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "std::string value(default_value);" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R025: entity construction maps JSON fields with default-empty fallback" {
  #R025-T01: Entity construction maps JSON sender/recipient/subject/id/receivedAt with empty-string fallbacks.
  run rg -F "OutlookMailcart::OutlookMailcart(const OutlookJsonObject &json_object)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'json_object.stringFieldOrDefault("sender", "")' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'message_id_(json_object.stringFieldOrDefault("id", ""))' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R030: messageId/receivedAt expose stored metadata via read-only accessors" {
  #R030-T01: messageId() and receivedAt() expose stored metadata through read-only accessors.
  run rg -F "const std::string &OutlookMailcart::messageId() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "const std::string &OutlookMailcart::receivedAt() const" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R035: type() reports the stable outlook_mailcart identifier" {
  #R035-T01: type() reports the stable outlook_mailcart identifier.
  run rg -F "std::string OutlookMailcart::type() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'std::string outlook_type = "outlook_mailcart";' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R040: attachment count parser accepts only validated positive integers" {
  #R040-T01: Attachment-count parsing uses strtol validation and only accepts fully parsed positive integers.
  run rg -F "int ParseAttachmentCount(const OutlookJsonObject &json_object)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "std::strtol(attachment_count_text.c_str()" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "parsed_value > 0" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R045: attachment builder reads indexed fields and appends attachments" {
  #R045-T01: Attachment-row builder reads indexed fields and appends one attachment per parsed index.
  run rg -F "std::vector<OutlookAttachment> BuildAttachmentsFromJson(" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F '"attachment" + std::to_string(attachment_index)' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "attachments.emplace_back(" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R050: attachment value type stores and exposes immutable fields" {
  #R050-T01: Attachment ctor/accessors preserve stored id/name/type/size state.
  run rg -F "OutlookAttachment::OutlookAttachment(" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "const std::string &OutlookAttachment::fileName() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "int OutlookAttachment::sizeInBytes() const" "${SRC}"
  [ "$status" -eq 0 ]
}
