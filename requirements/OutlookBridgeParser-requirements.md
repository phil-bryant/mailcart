# Outlook Bridge Parser Requirements

## Scope

Applies to the Objective-C++ payload parser in `macos_app/Bridge/OutlookBridgeParser.h` and
`macos_app/Bridge/OutlookBridgeParser.mm`, which maps Graph JSON payloads into C++ `OutlookJsonObject` domain values.

R035  Statement: Resolve message read requests by id with empty-field fallback for unknown ids.
Design: `BridgeOutlookParser::ParseMessagePayload` maps sender/recipient using Graph `emailAddress.address` fields,
splits body content by `contentType` into text/html, expands attachment records, and falls back to a deterministic
requested-id-plus-empty-field shape when the payload is empty. `ParseSearchPayload` deserializes the pre-filtered
summary payload built by the Graph HTTP client.
Tests:
- Read a known Graph id and verify DTO field mapping including sender/recipient email addresses.
- Read an unknown/unavailable id and verify the returned message preserves empty values for non-id fields.

## Changelog

- 2026-06-05: Extracted from the monolithic Bridge requirements doc; owns Graph payload parsing (R035).
