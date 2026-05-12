# MimeContent Requirements

## Scope

Applies to `cpp_core/src/mime_content.cpp`.

R001  Statement: Normalize empty MIME content types to an explicit unknown media type.
Design: `NormalizeContentType` replaces empty values with `application/unknown` in constructor and setter paths.
Tests:
- Construct `MimeContent("", "body")` and verify `contentType()` returns `application/unknown`.
- Call `SetContentType("")` and verify `contentType()` returns `application/unknown`.

R005  Statement: Preserve initialized content type and body values through accessors.
Design: Constructor stores normalized content type plus raw content; accessors return references to stored values.
Tests:
- Construct `MimeContent("text/plain", "hello")` and verify `contentType()` is `text/plain`.
- Construct `MimeContent("text/plain", "hello")` and verify `content()` is `hello`.

R010  Statement: Detect plain-text payloads by exact MIME type match.
Design: `isPlainText()` returns true only when stored content type equals `text/plain`.
Tests:
- Construct `MimeContent::PlainText("x")` and verify `isPlainText()` is true.
- Construct `MimeContent("text/plain; charset=utf-8", "x")` and verify `isPlainText()` is false.

R015  Statement: Detect HTML payloads by exact MIME type match.
Design: `isHtml()` returns true only when stored content type equals `text/html`.
Tests:
- Construct `MimeContent::Html("<p>x</p>")` and verify `isHtml()` is true.
- Construct `MimeContent("text/html; charset=utf-8", "<p>x</p>")` and verify `isHtml()` is false.

R020  Statement: Report empty payload state from message content only.
Design: `empty()` delegates emptiness check to `content_.empty()` regardless of MIME type.
Tests:
- Construct `MimeContent("text/plain", "")` and verify `empty()` is true.
- Construct `MimeContent("application/octet-stream", "x")` and verify `empty()` is false.

R025  Statement: Allow content type updates with normalization semantics.
Design: `SetContentType` applies `NormalizeContentType` before assigning new content type.
Tests:
- Set content type to `text/html` and verify `contentType()` updates.
- Set content type to empty string and verify fallback to `application/unknown`.

R030  Statement: Allow content payload replacement without content-type side effects.
Design: `SetContent` assigns provided content to internal payload while leaving current content type unchanged.
Tests:
- Set initial type to `text/plain`, call `SetContent("updated")`, and verify `contentType()` stays `text/plain`.
- Verify `content()` returns the updated payload after `SetContent`.

R035  Statement: Provide a canonical plain-text factory constructor.
Design: `PlainText(content)` returns `MimeContent("text/plain", content)`.
Tests:
- Call `MimeContent::PlainText("hello")` and verify `contentType()` is `text/plain`.
- Verify returned object `content()` equals `hello`.

R040  Statement: Provide a canonical HTML factory constructor.
Design: `Html(content)` returns `MimeContent("text/html", content)`.
Tests:
- Call `MimeContent::Html("<h1>x</h1>")` and verify `contentType()` is `text/html`.
- Verify returned object `content()` equals `<h1>x</h1>`.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `cpp_core/src/mime_content.cpp`.
