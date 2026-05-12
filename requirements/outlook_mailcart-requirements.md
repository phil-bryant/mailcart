# OutlookMailcart Requirements

## Scope

Applies to `cpp_core/src/outlook_mailcart.cpp`.

R001  Statement: Build MIME body content from JSON with text-first precedence.
Design: MIME builder selects plain-text body when `bodyText` is non-empty, else HTML body when `bodyHtml` is non-empty.
Tests:
- Provide both `bodyText` and `bodyHtml` fields and verify resulting MIME content is plain text.
- Provide only `bodyHtml` and verify resulting MIME content is HTML.

R005  Statement: Fallback to unknown empty MIME payload when no body fields are present.
Design: MIME builder initializes `MimeContent("application/unknown", "")` and retains it when both body fields are empty.
Tests:
- Provide JSON without body fields and verify MIME content type is `application/unknown` and content is empty.
- Provide empty `bodyText` and empty `bodyHtml` values and verify unknown empty MIME fallback.

R010  Statement: Support mutable string-field insertion into JSON object wrappers.
Design: `OutlookJsonObject::SetStringField` stores key/value pairs in an internal string map.
Tests:
- Insert a key/value pair and verify lookup by key returns inserted value.
- Insert the same key twice and verify latest value is returned.

R015  Statement: Report field presence by exact key membership.
Design: `hasField` returns true only when the key exists in the internal map.
Tests:
- Set key `id` and verify `hasField("id")` is true.
- Verify `hasField("missing")` is false when key was never inserted.

R020  Statement: Return default values for missing JSON string fields.
Design: `stringFieldOrDefault` returns stored value when key exists; otherwise returns caller-provided default string.
Tests:
- Query existing key and verify returned value matches stored map value.
- Query missing key with default and verify method returns the provided default string.

R025  Statement: Materialize Outlook mailcart entities from JSON string fields with default-empty fallback.
Design: `OutlookMailcart` constructor maps sender, recipient, subject, id, and receivedAt via `stringFieldOrDefault(..., "")`.
Tests:
- Provide all mapped JSON fields and verify base mailcart fields plus message metadata match source values.
- Omit one or more mapped fields and verify omitted values default to empty strings.

R030  Statement: Expose Outlook-specific message metadata through read-only accessors.
Design: `messageId()` and `receivedAt()` return references to stored metadata fields.
Tests:
- Construct `OutlookMailcart` with id and timestamp values and verify both accessors return expected values.

R035  Statement: Report a stable Outlook entity type identifier.
Design: `type()` returns the literal value `outlook_mailcart`.
Tests:
- Construct `OutlookMailcart` and verify `type()` returns `outlook_mailcart`.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `cpp_core/src/outlook_mailcart.cpp`.
