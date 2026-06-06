# OutlookClient Requirements

## Scope

Applies to `cpp_core/src/outlook_client.cpp`.

R001  Statement: Coerce negative search limits to zero before service calls.
Design: `NormalizeLimit` returns requested limit unchanged when non-negative, otherwise returns zero.
Tests:
- R001-T01: Negative search limits coerce to zero while non-negative limits pass through unchanged.

R005  Statement: Store Outlook summary identity, preview, and received-at fields as immutable summary state.
Design: `OutlookMailcartSummary` constructor captures message id/subject/preview/receivedAt; accessors expose stored values.
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

R040  Statement: Store search-result summaries, pagination cursor, and error message as immutable result state exposed through read-only accessors.
Design: `OutlookSearchResult` constructor moves `summaries`/`next_cursor`/`error_message` into members, and `summaries()`/`nextCursor()`/`errorMessage()` return const references.
Tests:
- R040-T01: Search-result state stores summaries/cursor/error and exposes them through read-only accessors.

R045  Statement: Paginate search via cursor markers and surface next-cursor and error markers from parsed objects.
Design: `SearchMailcartsPage` normalizes the limit, rewrites cursor requests as `"__cursor__"+cursor`, and routes `__nextCursor`/`__error` marker objects into result metadata while mapping data objects into summaries.
Tests:
- R045-T01: Cursor searches rewrite query and surface `__nextCursor`/`__error` markers into result metadata.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `cpp_core/src/outlook_client.cpp`.
- 2026-06-06: Added R040/R045 and broadened R005 to include received-at accessors and cursor-page metadata behavior.
