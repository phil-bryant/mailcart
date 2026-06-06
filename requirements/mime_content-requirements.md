# MimeContent Requirements

## Scope

Applies to `cpp_core/src/mime_content.cpp`.

R001  Statement: Normalize empty MIME content types to an explicit unknown media type.
Design: `NormalizeContentType` replaces empty values with `application/unknown` in constructor and setter paths.
Tests:
- R001-T01: Empty MIME content types normalize to `application/unknown` in constructor and setter paths.

R005  Statement: Preserve initialized content type and body values through accessors.
Design: Constructor stores normalized content type plus raw content; accessors return references to stored values.
Tests:
- R005-T01: Constructor stores the normalized content type and raw content exposed through accessors.

R010  Statement: Detect plain-text payloads by exact MIME type match.
Design: `isPlainText()` returns true only when stored content type equals `text/plain`.
Tests:
- R010-T01: `isPlainText()` returns true only for an exact `text/plain` content type match.

R015  Statement: Detect HTML payloads by exact MIME type match.
Design: `isHtml()` returns true only when stored content type equals `text/html`.
Tests:
- R015-T01: `isHtml()` returns true only for an exact `text/html` content type match.

R020  Statement: Report empty payload state from message content only.
Design: `empty()` delegates emptiness check to `content_.empty()` regardless of MIME type.
Tests:
- R020-T01: `empty()` reports payload emptiness from message content only, ignoring MIME type.

R025  Statement: Allow content type updates with normalization semantics.
Design: `SetContentType` applies `NormalizeContentType` before assigning new content type.
Tests:
- R025-T01: `SetContentType` applies normalization before assigning the new content type.

R030  Statement: Allow content payload replacement without content-type side effects.
Design: `SetContent` assigns provided content to internal payload while leaving current content type unchanged.
Tests:
- R030-T01: `SetContent` replaces the payload without changing the stored content type.

R035  Statement: Provide a canonical plain-text factory constructor.
Design: `PlainText(content)` returns `MimeContent("text/plain", content)`.
Tests:
- R035-T01: `PlainText` factory builds a `text/plain` MIME object from the provided content.

R040  Statement: Provide a canonical HTML factory constructor.
Design: `Html(content)` returns `MimeContent("text/html", content)`.
Tests:
- R040-T01: `Html` factory builds a `text/html` MIME object from the provided content.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `cpp_core/src/mime_content.cpp`.
