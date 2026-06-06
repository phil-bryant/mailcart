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
- Run with token unset and verify search/read produce deterministic empty-value responses.
- Run with token set and verify Graph fetch payloads are handed to the parser.
- Mock Graph 401 and verify refresh-script invocation and single retry behavior.

R020  Statement: Perform case-insensitive search matching over subject and preview fields.
Design: Search payload builder normalizes subject/preview/query text and includes entries when the query is empty or
found in either field.
Tests:
- Query with varied letter case and verify equivalent result sets.
- Query with empty text and verify all fetched messages are eligible before limit trimming.

R025  Statement: Enforce non-negative and capped search result limits.
Design: Search payload builder coerces negative limits to zero and returns at most the requested number of matched
summaries.
Tests:
- Search with a negative limit and verify zero results.
- Search with a positive limit below available matches and verify truncation to that exact count.

R030  Statement: Return summary-only payload fields in search responses.
Design: Search payload builder serializes filtered Graph results using only `id`, `subject`, `preview`, and
`receivedAt` fields, omitting body/sender/recipient data, before parser conversion into summary DTOs.
Tests:
- Execute a search and verify each summary result includes message id, subject, and preview values.
- Verify the search builder omits body/sender/recipient fields from serialized summaries.

## Changelog

- 2026-06-05: Extracted from the monolithic Bridge requirements doc; owns token resolution, GET transport, and the
  search/message payload builders (R015/R020/R025/R030).
