# Mailcart Requirements

## Scope

Applies to `cpp_core/src/mailcart.cpp`.

R001  Statement: Normalize empty sender and recipient addresses to a safe local placeholder.
Design: `NormalizeAddress` replaces empty address values with `unknown@local` before persistence.
Tests:
- Construct `Mailcart` with empty sender and recipient and verify both accessors return `unknown@local`.
- Construct `Mailcart` with non-empty sender and recipient and verify original values are preserved.

R005  Statement: Normalize empty subjects to a non-empty default label.
Design: `NormalizeSubject` replaces empty subject values with `(no subject)` in constructor and subject mutator paths.
Tests:
- Construct `Mailcart` with empty subject and verify `subject()` returns `(no subject)`.
- Call `SetSubject("")` on an existing `Mailcart` and verify subject is normalized to `(no subject)`.

R010  Statement: Support plain-text body initialization through a convenience constructor.
Design: The string-body constructor delegates to the MIME constructor using `MimeContent::PlainText(body)`.
Tests:
- Construct `Mailcart` with string body and verify `mimeContent().contentType()` is `text/plain`.
- Construct `Mailcart` with string body and verify `body()` equals the provided body string.

R015  Statement: Expose sender, recipient, subject, and body through read-only accessors.
Design: Accessors return references to stored sender/recipient/subject values and `mime_content_.content()` for body.
Tests:
- Construct `Mailcart` and verify `sender()`, `recipient()`, and `subject()` match normalized inputs.
- Set MIME content and verify `body()` reflects the MIME content payload.

R020  Statement: Update subject through normalized mutation behavior.
Design: `SetSubject` applies `NormalizeSubject` before assigning to stored subject state.
Tests:
- Call `SetSubject("Updated Subject")` and verify `subject()` returns the updated value.
- Call `SetSubject("")` and verify `subject()` returns `(no subject)`.

R025  Statement: Update body through plain-text MIME conversion.
Design: `SetBody` replaces stored MIME content with `MimeContent::PlainText(body)`.
Tests:
- Call `SetBody("new body")` and verify `mimeContent().contentType()` is `text/plain`.
- Call `SetBody("new body")` and verify `body()` returns `new body`.

R030  Statement: Support direct MIME content replacement for non-plain payloads.
Design: `SetMimeContent` moves the provided `MimeContent` into internal state without additional normalization.
Tests:
- Call `SetMimeContent(MimeContent::Html("<b>x</b>"))` and verify `mimeContent().isHtml()` is true.
- Verify `body()` reflects content from the last assigned MIME object.

R035  Statement: Report a stable domain type identifier for base mailcart entities.
Design: `type()` returns the literal value `mailcart`.
Tests:
- Construct `Mailcart` and verify `type()` returns `mailcart`.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `cpp_core/src/mailcart.cpp`.
