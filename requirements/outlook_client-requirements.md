# OutlookClient Requirements

## Scope

Applies to `cpp_core/src/outlook_client.cpp`.

R001  Statement: Coerce negative search limits to zero before service calls.
Design: `NormalizeLimit` returns requested limit unchanged when non-negative, otherwise returns zero.
Tests:
- R001-T01: Negative search limits coerce to zero while non-negative limits pass through unchanged.

R005  Statement: Store Outlook summary identity and preview fields as immutable summary state.
Design: `OutlookMailcartSummary` constructor captures message id, subject, and preview; accessors expose stored values.
Tests:
- R005-T01: Summary constructor captures id/subject/preview as immutable state exposed via accessors.

R010  Statement: Expose polymorphic cleanup hooks for gateway and parser abstractions.
Design: `OutlookServiceGateway` and `OutlookPayloadParser` provide out-of-line virtual destructors.
Tests:
- R010-T01: Gateway and parser abstractions provide out-of-line virtual destructors.

R015  Statement: Bind client operations to injected gateway and parser dependencies.
Design: `OutlookClient` constructor stores references to gateway and parser for all read/search interactions.
Tests:
- R015-T01: Client constructor binds the injected gateway and parser references.

R020  Statement: Fetch and parse search payloads through gateway-parser pipeline.
Design: `SearchMailcarts` calls gateway `FetchSearchPayload(query, normalized_limit)` and parses with `ParseSearchPayload`.
Tests:
- R020-T01: Search fetches the payload via the gateway then parses it through the parser pipeline.

R025  Statement: Map parsed search objects to summary DTOs with default-empty fallback fields.
Design: For each parsed object, mapping reads `id`, `subject`, and `preview` using `stringFieldOrDefault(..., "")`.
Tests:
- R025-T01: Parsed objects map to summaries reading id/subject/preview with empty-string fallbacks.

R030  Statement: Preserve parser result ordering and cardinality in search results.
Design: Search mapping iterates parser output sequentially and appends one summary per parsed object.
Tests:
- R030-T01: Search mapping preserves parser ordering and one summary per parsed object.

R035  Statement: Fetch and parse message payloads before constructing Outlook mailcart entities.
Design: `ReadMailcart` calls gateway message fetch, parses payload to `OutlookJsonObject`, and constructs `OutlookMailcart`.
Tests:
- R035-T01: `ReadMailcart` fetches and parses a message payload before constructing the entity.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `cpp_core/src/outlook_client.cpp`.
