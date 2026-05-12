# OutlookClient Requirements

## Scope

Applies to `cpp_core/src/outlook_client.cpp`.

R001  Statement: Coerce negative search limits to zero before service calls.
Design: `NormalizeLimit` returns requested limit unchanged when non-negative, otherwise returns zero.
Tests:
- Call `SearchMailcarts("q", -1)` with a gateway spy and verify fetch uses limit `0`.
- Call `SearchMailcarts("q", 25)` and verify fetch uses limit `25`.

R005  Statement: Store Outlook summary identity and preview fields as immutable summary state.
Design: `OutlookMailcartSummary` constructor captures message id, subject, and preview; accessors expose stored values.
Tests:
- Construct `OutlookMailcartSummary("id-1", "Sub", "Prev")` and verify each accessor returns its field.
- Verify accessor values remain stable across repeated reads.

R010  Statement: Expose polymorphic cleanup hooks for gateway and parser abstractions.
Design: `OutlookServiceGateway` and `OutlookPayloadParser` provide out-of-line virtual destructors.
Tests:
- Delete derived gateway/parser instances via base pointers and verify no undefined behavior occurs.

R015  Statement: Bind client operations to injected gateway and parser dependencies.
Design: `OutlookClient` constructor stores references to gateway and parser for all read/search interactions.
Tests:
- Construct client with fake dependencies and verify subsequent calls use the provided fakes.

R020  Statement: Fetch and parse search payloads through gateway-parser pipeline.
Design: `SearchMailcarts` calls gateway `FetchSearchPayload(query, normalized_limit)` and parses with `ParseSearchPayload`.
Tests:
- Instrument gateway/parser fakes and verify both methods are called once per search invocation.
- Verify parser input equals raw payload returned by gateway.

R025  Statement: Map parsed search objects to summary DTOs with default-empty fallback fields.
Design: For each parsed object, mapping reads `id`, `subject`, and `preview` using `stringFieldOrDefault(..., "")`.
Tests:
- Provide parsed objects with all fields and verify mapped summaries match expected values.
- Omit one or more fields and verify missing values map to empty strings.

R030  Statement: Preserve parser result ordering and cardinality in search results.
Design: Search mapping iterates parser output sequentially and appends one summary per parsed object.
Tests:
- Return parsed objects in a known order and verify output summary order is identical.
- Return N parsed objects and verify output vector size equals N.

R035  Statement: Fetch and parse message payloads before constructing Outlook mailcart entities.
Design: `ReadMailcart` calls gateway message fetch, parses payload to `OutlookJsonObject`, and constructs `OutlookMailcart`.
Tests:
- Verify `ReadMailcart` passes requested message id to gateway fetch call.
- Verify parsed message fields are reflected in returned `OutlookMailcart`.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for `cpp_core/src/outlook_client.cpp`.
