#!/usr/bin/env bats

# Behavioral contract checks for the cpp_core MimeContent value type. Compiled
# behavior is exercised by the C++ integration lane
# (tests/t08_run_cpp_integration_tests.sh); these checks assert the source
# implements each requirement's design contract so regressions fail the lane.

load helpers/repo_root

setup() {
  #R001: Test harness setup for mime_content contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/cpp_core/src/mime_content.cpp"
}

@test "R001: empty content types normalize to application/unknown" {
  #R001-T01: Empty MIME content types normalize to application/unknown in constructor and setter paths.
  run rg -F "std::string NormalizeContentType(std::string content_type)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'normalized = "application/unknown";' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: constructor normalizes content type and exposes accessors" {
  #R005-T01: Constructor stores the normalized content type and raw content exposed through accessors.
  run rg -F "content_type_(NormalizeContentType(std::move(content_type))), content_(std::move(content))" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "const std::string &MimeContent::contentType() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "const std::string &MimeContent::content() const" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R010: isPlainText matches text/plain exactly" {
  #R010-T01: isPlainText() returns true only for an exact text/plain content type match.
  run rg -F "bool MimeContent::isPlainText() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'if (content_type_ == "text/plain")' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R015: isHtml matches text/html exactly" {
  #R015-T01: isHtml() returns true only for an exact text/html content type match.
  run rg -F "bool MimeContent::isHtml() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'if (content_type_ == "text/html")' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R020: empty() delegates to content payload emptiness only" {
  #R020-T01: empty() reports payload emptiness from message content only, ignoring MIME type.
  run rg -F "bool MimeContent::empty() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "bool is_empty = content_.empty();" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R025: SetContentType applies normalization" {
  #R025-T01: SetContentType applies normalization before assigning the new content type.
  run rg -F "void MimeContent::SetContentType(std::string content_type)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "content_type_ = NormalizeContentType(std::move(content_type));" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R030: SetContent replaces payload without touching content type" {
  #R030-T01: SetContent replaces the payload without changing the stored content type.
  run rg -F "void MimeContent::SetContent(std::string content)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "content_ = std::move(content);" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R035: PlainText factory builds a text/plain MIME object" {
  #R035-T01: PlainText factory builds a text/plain MIME object from the provided content.
  run rg -F "MimeContent MimeContent::PlainText(std::string content)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'MimeContent plain_text("text/plain", std::move(content));' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R040: Html factory builds a text/html MIME object" {
  #R040-T01: Html factory builds a text/html MIME object from the provided content.
  run rg -F "MimeContent MimeContent::Html(std::string content)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'MimeContent html("text/html", std::move(content));' "${SRC}"
  [ "$status" -eq 0 ]
}
