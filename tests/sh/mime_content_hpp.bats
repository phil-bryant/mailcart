#!/usr/bin/env bats

# Interface contract checks for the cpp_core MimeContent header. The compiled
# behavior is exercised by the C++ integration lane; these checks assert the
# header declares the interface each requirement depends on.

load helpers/repo_root

setup() {
  #R001: Test harness setup for mime_content_hpp contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  HDR="${REPO_ROOT}/cpp_core/include/mime_content.hpp"
}

@test "R001: header declares constructor, accessors, predicates, mutators, and factories" {
  #R001-T01: Verify the header declares the constructor, accessors, predicates, mutators, and static factories.
  run rg -F "MimeContent(std::string content_type, std::string content);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] const std::string &contentType() const;" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] bool isPlainText() const;" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] bool isHtml() const;" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "void SetContentType(std::string content_type);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] static MimeContent PlainText(std::string content);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] static MimeContent Html(std::string content);" "${HDR}"
  [ "$status" -eq 0 ]
}
