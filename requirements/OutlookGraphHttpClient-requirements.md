# Outlook Graph HTTP Client Requirements

## Scope

Applies to the Microsoft Graph HTTP read client in `macos_app/Bridge/OutlookGraphHttpClient.h` and
`macos_app/Bridge/OutlookGraphHttpClient.mm`. This unit owns token resolution, authenticated GET transport, and the
search/message/attachment payload builders. Folder/move POST behavior lives in the message-mover unit.

R015  Statement: Resolve live Graph payloads through runtime token-aware client behavior.
Design: Client prefers a valid access token from the shared cache file, falls back to `OUTLOOK_GRAPH_TOKEN` from the
runtime environment, refreshes credentials on Graph HTTP 401 via `scripts/refresh_graph_token.py`, retries once, and
returns deterministic empty payloads when no token is available.
Tests:
- R015-T01: Client resolves the Graph token from cache/`OUTLOOK_GRAPH_TOKEN`, refreshes via `scripts/refresh_graph_token.py` on HTTP 401, and retries once.

R020  Statement: Perform case-insensitive search matching over subject and preview fields.
Design: Search payload builder normalizes subject/preview/query text and includes entries when the query is empty or
found in either field.
Tests:
- R020-T01: Search builder normalizes subject/preview/query text for case-insensitive matching.

R025  Statement: Enforce non-negative and capped search result limits.
Design: Search payload builder coerces negative limits to zero and returns at most the requested number of matched
summaries.
Tests:
- R025-T01: Search builder coerces negative limits to zero and caps results at the requested count.

R030  Statement: Return summary-only payload fields in search responses.
Design: Search payload builder serializes filtered Graph results using only `id`, `subject`, `preview`, and
`receivedAt` fields, omitting body/sender/recipient data, before parser conversion into summary DTOs.
Tests:
- R030-T01: Search summaries serialize only `id`/`subject`/`preview` fields and omit body/sender/recipient data.

R035  Statement: Extract pagination cursors from `__cursor__`-prefixed search query markers.
Design: `ExtractCursorFromQuery` converts query text to `NSString` and returns the substring following `kCursorPrefix` when present.
Tests:
- R035-T01: Cursor extraction recognizes `__cursor__`-prefixed queries and returns the suffix cursor value.

R040  Statement: Normalize attachment file names to a safe basename with deterministic fallback.
Design: `NormalizedAttachmentFileName` trims whitespace, replaces slash/backslash path separators, and falls back to `attachment.bin` when name input is empty.
Tests:
- R040-T01: Attachment filename normalization falls back to `attachment.bin` and replaces path separators with underscores.

R045  Statement: Build normalized Graph attachment payload arrays for message-read responses.
Design: `BuildGraphAttachmentPayload` fetches `/messages/{id}/attachments` and maps each record into id/name/contentType/size dictionaries with safe defaults.
Tests:
- R045-T01: Attachment payload builder fetches message attachments and normalizes id/name/contentType/size fields.

R050  Statement: Build deterministic single-message payloads merged with normalized attachments.
Design: `BuildGraphMessagePayload` seeds a fallback payload shape, fetches selected message fields from Graph, and merges `BuildGraphAttachmentPayload` results into `attachments`.
Tests:
- R050-T01: Message payload builder emits fallback shape and merges normalized attachments into fetched message dictionaries.

## Changelog

- 2026-06-05: Extracted from the monolithic Bridge requirements doc; owns token resolution, GET transport, and the
  search/message payload builders (R015/R020/R025/R030).
- 2026-06-06: Added R035/R040/R045/R050 for cursor extraction, attachment normalization/building, and merged message payload behavior.
