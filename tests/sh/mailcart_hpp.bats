#!/usr/bin/env bats

# Interface contract checks for the cpp_core Mailcart header. The compiled
# behavior is exercised by the C++ integration lane; these checks assert the
# header declares the interface each requirement depends on.

load helpers/repo_root

setup() {
  #R001: Test harness setup for mailcart_hpp contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  HDR="${REPO_ROOT}/cpp_core/include/mailcart.hpp"
}

@test "R001: header declares constructors, accessors, mutators, and type()" {
  #R001-T01: Verify the header declares the constructors, read-only accessors, virtual mutators, and type().
  run rg -F "Mailcart(std::string sender, std::string recipient, std::string subject, std::string body);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] const std::string &sender() const;" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "virtual void SetSubject(std::string subject);" "${HDR}"
  [ "$status" -eq 0 ]
  run rg -F "[[nodiscard]] virtual std::string type() const;" "${HDR}"
  [ "$status" -eq 0 ]
}
