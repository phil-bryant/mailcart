# OutlookMailcart Header Requirements

## Scope

Applies to `cpp_core/include/outlook_mailcart.hpp`.

R001  Statement: Declare the Outlook mailcart interface consumed by the cpp_core implementation.
Design: The header declares the `OutlookJsonObject` wrapper (`SetStringField`/`hasField`/`stringFieldOrDefault`), the `OutlookAttachment` value type with accessors, and the `OutlookMailcart` entity deriving from `Mailcart` with its JSON constructor, message metadata accessors (`messageId`/`receivedAt`/`bodyText`/`bodyHtml`/`attachments`), and the `type()` override.
Tests:
- R001-T01: Verify the header declares the JSON object wrapper, attachment type, and the OutlookMailcart entity with its accessors and `type()` override.

## Changelog

- 2026-06-06: Initial requirements doc covering the `cpp_core/include/outlook_mailcart.hpp` interface for full-coverage traceability.
