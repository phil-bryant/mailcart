# Outlook Graph Conversions Requirements

## Scope

Applies to the Foundation/C++ conversion and JSON-normalization helpers in
`macos_app/Bridge/OutlookGraphConversions.h` and `macos_app/Bridge/OutlookGraphConversions.mm`.

R010  Statement: Normalize string conversion between Foundation and C++ payloads.
Design: `ToNSString` translates `std::string` to UTF-8 `NSString` with an empty-string result when allocation fails;
`ToStdString` translates `NSString` to `std::string`, using an empty string when UTF-8 extraction is null. Shared JSON
normalization helpers (`JsonStringOrEmpty`, `JsonDictionaryOrEmpty`, `JsonArrayOrEmpty`, `SerializeJsonObject`,
`ParseJsonObject`) build on these conversions for the Graph client and parser units.
Tests:
- R010-T01: `ToNSString`/`ToStdString` convert between `std::string` and `NSString` with null-safe empty-string fallbacks.

## Changelog

- 2026-06-05: Extracted from the monolithic Bridge requirements doc; owns string/JSON conversion helpers (R010).
