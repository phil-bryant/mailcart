# OutlookMailcart Requirements

## Scope

Applies to `cpp_core/src/outlook_mailcart.cpp`.

R001  Statement: Build MIME body content from JSON with text-first precedence.
Design: MIME builder selects plain-text body when `bodyText` is non-empty, else HTML body when `bodyHtml` is non-empty.
Tests:
- R001-T01: MIME body builder prefers plain text when `bodyText` is present, else HTML when `bodyHtml` is present.

R005  Statement: Fallback to unknown empty MIME payload when no body fields are present.
Design: MIME builder initializes `MimeContent("application/unknown", "")` and retains it when both body fields are empty.
Tests:
- R005-T01: Absent or empty body fields fall back to an empty `application/unknown` MIME payload.

R010  Statement: Support mutable string-field insertion into JSON object wrappers.
Design: `OutlookJsonObject::SetStringField` stores key/value pairs in an internal string map.
Tests:
- R010-T01: `SetStringField` stores key/value pairs in the internal field map.

R015  Statement: Report field presence by exact key membership.
Design: `hasField` returns true only when the key exists in the internal map.
Tests:
- R015-T01: `hasField` reports field presence by exact key membership.

R020  Statement: Return default values for missing JSON string fields.
Design: `stringFieldOrDefault` returns stored value when key exists; otherwise returns caller-provided default string.
Tests:
- R020-T01: `stringFieldOrDefault` returns the stored value for present keys and the caller default otherwise.

R025  Statement: Materialize Outlook mailcart entities from JSON string fields with default-empty fallback.
Design: `OutlookMailcart` constructor maps sender, recipient, subject, id, and receivedAt via `stringFieldOrDefault(..., "")`.
Tests:
- R025-T01: Entity construction maps JSON sender/recipient/subject/id/receivedAt with empty-string fallbacks.

R030  Statement: Expose Outlook-specific message metadata and body/attachment views through read-only accessors.
Design: `messageId()`/`receivedAt()`/`bodyText()`/`bodyHtml()`/`attachments()` return references to stored Outlook mailcart state.
Tests:
- R030-T01: `messageId()` and `receivedAt()` expose stored metadata through read-only accessors.

R035  Statement: Report a stable Outlook entity type identifier.
Design: `type()` returns the literal value `outlook_mailcart`.
Tests:
- R035-T01: `type()` reports the stable `outlook_mailcart` identifier.

R040  Statement: Parse a non-negative attachment count from the JSON `attachmentCount` field.
Design: `ParseAttachmentCount` uses `std::strtol` with full-consume validation and returns zero unless a strictly-positive integer is parsed.
Tests:
- R040-T01: Attachment-count parsing uses `strtol` validation and only accepts fully parsed positive integers.

R045  Statement: Build attachment rows from indexed JSON fields up to the parsed attachment count.
Design: `BuildAttachmentsFromJson` reads indexed `attachmentN{Id,Name,Type,Size}` fields with empty/zero fallbacks and emplaces one `OutlookAttachment` per index.
Tests:
- R045-T01: Attachment-row builder reads indexed fields and appends one attachment per parsed index.

R050  Statement: Represent an Outlook attachment as an immutable value type with read-only accessors.
Design: `OutlookAttachment` stores id/name/contentType/size in the constructor and exposes them through `attachmentId()`/`fileName()`/`contentType()`/`sizeInBytes()`.
Tests:
- R050-T01: Attachment ctor/accessors preserve stored id/name/type/size state.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `cpp_core/src/outlook_mailcart.cpp`.
- 2026-06-06: Added R040/R045/R050 and broadened R030 to include body and attachment accessors.
