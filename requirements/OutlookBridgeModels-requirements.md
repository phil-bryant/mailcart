# Outlook Bridge Models Requirements

## Scope

Applies to the immutable Objective-C DTO models in `macos_app/Bridge/OutlookBridgeModels.h` and
`macos_app/Bridge/OutlookBridgeModels.m`.

R005  Statement: Provide immutable Objective-C DTO models for mailcart summary and full mailcart payloads.
Design: `OutlookMailcartSummaryDTO` and `OutlookMailcartDTO` (with `OutlookSearchResultDTO` and `OutlookAttachmentDTO`)
expose readonly copied `NSString` properties, materialize values through designated initializers, and disallow
default initialization via `init NS_UNAVAILABLE`.
Tests:
- R005-T01: DTO models declare immutable copied properties through designated initializers with `init` made unavailable.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `macos_app/Bridge/*`.
- 2026-06-05: Split out from the monolithic Bridge requirements doc; this doc now scopes only the DTO models (R005).
