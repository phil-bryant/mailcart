# Mailcart Requirements

## Scope

Applies to `cpp_core/src/mailcart.cpp`.

R001  Statement: Normalize empty sender and recipient addresses to a safe local placeholder.
Design: `NormalizeAddress` replaces empty address values with `unknown@local` before persistence.
Tests:
- R001-T01: Empty sender/recipient addresses normalize to `unknown@local` while non-empty values are preserved.

R005  Statement: Normalize empty subjects to a non-empty default label.
Design: `NormalizeSubject` replaces empty subject values with `(no subject)` in constructor and subject mutator paths.
Tests:
- R005-T01: Empty subjects normalize to the `(no subject)` label in constructor and mutator paths.

R010  Statement: Support plain-text body initialization through a convenience constructor.
Design: The string-body constructor delegates to the MIME constructor using `MimeContent::PlainText(body)`.
Tests:
- R010-T01: The string-body constructor delegates to the plain-text MIME constructor.

R015  Statement: Expose sender, recipient, subject, body, and MIME payload through read-only accessors.
Design: Accessors return references to stored sender/recipient/subject values, `mime_content_.content()` for body, and `mimeContent()` for MIME state.
Tests:
- R015-T01: Sender/recipient/subject/body expose read-only accessors over stored state.

R020  Statement: Update subject through normalized mutation behavior.
Design: `SetSubject` applies `NormalizeSubject` before assigning to stored subject state.
Tests:
- R020-T01: `SetSubject` applies subject normalization before assigning stored state.

R025  Statement: Update body through plain-text MIME conversion.
Design: `SetBody` replaces stored MIME content with `MimeContent::PlainText(body)`.
Tests:
- R025-T01: `SetBody` replaces stored content via plain-text MIME conversion.

R030  Statement: Support direct MIME content replacement for non-plain payloads.
Design: `SetMimeContent` moves the provided `MimeContent` into internal state without additional normalization.
Tests:
- R030-T01: `SetMimeContent` moves MIME content without additional normalization.

R035  Statement: Report a stable domain type identifier for base mailcart entities.
Design: `type()` returns the literal value `mailcart`.
Tests:
- R035-T01: `type()` reports the stable `mailcart` identifier.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `cpp_core/src/mailcart.cpp`.
- 2026-06-06: Broadened R015 wording to include the `mimeContent()` accessor.
