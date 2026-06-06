# Mailcart Header Requirements

## Scope

Applies to `cpp_core/include/mailcart.hpp`.

R001  Statement: Declare the Mailcart entity interface consumed by the cpp_core implementation and bridge.
Design: The header declares both constructors (string body and MIME body), read-only `sender()`/`recipient()`/`subject()`/`body()`/`mimeContent()` accessors, the virtual `SetSubject`/`SetBody`/`SetMimeContent` mutators, a virtual `type()`, and the private stored fields.
Tests:
- R001-T01: Verify the header declares the constructors, read-only accessors, virtual mutators, and `type()`.

## Changelog

- 2026-06-06: Initial requirements doc covering the `cpp_core/include/mailcart.hpp` interface for full-coverage traceability.
