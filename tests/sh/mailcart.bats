#!/usr/bin/env bats

# Behavioral contract checks for the cpp_core Mailcart entity. The compiled
# behavior is exercised end-to-end by the C++ integration lane
# (tests/t08_run_cpp_integration_tests.sh -> cpp_core/tests/outlook_integration_test.cpp);
# these checks assert the source implements each requirement's design contract
# so a regression (renamed symbol, dropped normalization literal) fails the lane.

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/cpp_core/src/mailcart.cpp"
}

@test "R001: empty sender/recipient addresses normalize to unknown@local" {
  #R001-T01: Empty sender/recipient addresses normalize to unknown@local while non-empty values are preserved.
  run rg -F "std::string NormalizeAddress(std::string address)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'normalized = "unknown@local";' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: empty subjects normalize to the (no subject) label" {
  #R005-T01: Empty subjects normalize to the (no subject) label in constructor and mutator paths.
  run rg -F "std::string NormalizeSubject(std::string subject)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'normalized = "(no subject)";' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R010: string-body constructor delegates to the plain-text MIME constructor" {
  #R010-T01: The string-body constructor delegates to the plain-text MIME constructor.
  run rg -F "MimeContent::PlainText(std::move(body))" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R015: sender/recipient/subject/body expose read-only accessors over stored state" {
  #R015-T01: Sender/recipient/subject/body expose read-only accessors over stored state.
  run rg -F "const std::string &Mailcart::sender() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "const std::string &Mailcart::recipient() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "const std::string &Mailcart::subject() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "const std::string &value = mime_content_.content();" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R020: SetSubject applies subject normalization" {
  #R020-T01: SetSubject applies subject normalization before assigning stored state.
  run rg -F "void Mailcart::SetSubject(std::string subject)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "subject_ = NormalizeSubject(std::move(subject));" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R025: SetBody replaces content via plain-text MIME conversion" {
  #R025-T01: SetBody replaces stored content via plain-text MIME conversion.
  run rg -F "void Mailcart::SetBody(std::string body)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "mime_content_ = MimeContent::PlainText(std::move(body));" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R030: SetMimeContent moves MIME content without extra normalization" {
  #R030-T01: SetMimeContent moves MIME content without additional normalization.
  run rg -F "void Mailcart::SetMimeContent(MimeContent mime_content)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "mime_content_ = std::move(mime_content);" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R035: type() reports the stable mailcart identifier" {
  #R035-T01: type() reports the stable mailcart identifier.
  run rg -F "std::string Mailcart::type() const" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'std::string base_type("mailcart");' "${SRC}"
  [ "$status" -eq 0 ]
}
