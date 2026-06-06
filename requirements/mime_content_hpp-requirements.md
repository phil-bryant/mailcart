# MimeContent Header Requirements

## Scope

Applies to `cpp_core/include/mime_content.hpp`.

R001  Statement: Declare the MimeContent value type interface consumed by the cpp_core implementation.
Design: The header declares the `MimeContent(content_type, content)` constructor, read-only `contentType()`/`content()` accessors, the `isPlainText()`/`isHtml()`/`empty()` predicates, the `SetContentType`/`SetContent` mutators, the static `PlainText`/`Html` factories, and the private stored fields.
Tests:
- R001-T01: Verify the header declares the constructor, accessors, predicates, mutators, and static factories.

## Changelog

- 2026-06-06: Initial requirements doc covering the `cpp_core/include/mime_content.hpp` interface for full-coverage traceability.
