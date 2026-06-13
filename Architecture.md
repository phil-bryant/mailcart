# Architecture

Mailcart is the Outlook/Microsoft Graph integration layer of the eggnest workspace. It owns local email
search, per-message body fetch, and folder-move operations, and delivers them through two surfaces: a native
macOS SwiftUI app for humans and an HTTPS FastAPI for automation (matchy and classy's proxy).

The cross-repo system landscape is canonical in the eggnest root [`../Architecture.md`](../Architecture.md);
this document covers mailcart's internal architecture.

## Ownership

- Mailcart owns the local email search/body/move API contract (search `R020`, per-message `R035`, move `R025`).
- Mailcart owns its Microsoft Graph OAuth token lifecycle (1psa bootstrap, cache, refresh, 401 retry).
- Mailcart owns Aho-Corasick scoped-search matching for Outlook message fields (`R050`).
- Consumers are matchy (`../matchy/matchy/mailcart_client.py`) and classy's `/v1/matchy/*` proxy. Mailcart does
  not read or write the Teller DB; it is a stateless Graph proxy.

## System Landscape

```text
+-----------------------------------------------------------------------------------+
|                                  CONSUMERS                                        |
|   matchy (mailcart_client.py)   classy (/v1/matchy/* proxy)   human operator      |
+----------------------+------------------------------------------+-----------------+
                       | HTTPS :8788                              | SwiftUI
                       v                                          v
+-----------------------------------------+   +-----------------------------------------+
| scripts/matchy_mailcart_api.py          |   | macos_app/UI/                           |
| - FastAPI, HTTPS-only (127.0.0.1:8788)  |   | - OutlookMailContentView (split view)   |
| - /health, search, get, move            |   | - OutlookMailViewModel (@MainActor)     |
| - Aho-Corasick scoped query matcher     |   | - HTMLBodyView (WebKit)                 |
+--------------------+--------------------+   +--------------------+--------------------+
                     | requests                                   | OutlookClientBridge
                     v                                            v
+-----------------------------------------+   +-----------------------------------------+
| scripts/graph_token.py                  |   | macos_app/Bridge/ (ObjC++)              |
| GraphTokenManager: 1psa -> cache ->     |<--| - synchronous Graph HTTP                |
| refresh on 401                          |   | - implements gateway + parser           |
+--------------------+--------------------+   +--------------------+--------------------+
                     |                                            | cpp_core domain model
                     +---------------------+----------------------+
                                           v
                            Microsoft Graph v1.0 (https://graph.microsoft.com)
```

## Delivery Surfaces

Mailcart ships the same domain capability through two independent surfaces:

- macOS app (`macos_app/`): human-facing browse/search/sort/paginate/read with HTML and plain-text body modes.
  Launched via `make run`.
- HTTPS API (`scripts/matchy_mailcart_api.py`): programmatic search/get/move on `https://127.0.0.1:8788`.
  Plain HTTP is rejected at startup. Launched via `make run-api`.

## Layered Stack (macOS app path)

```text
Swift UI (macos_app/UI/)            SwiftUI views + @MainActor view model
        | OutlookClientBridge
ObjC++ bridge (macos_app/Bridge/)   Graph HTTP, JSON parse, DTO marshalling, 401 -> refresh
        | implements
C++ core (cpp_core/)                domain model + client orchestration
```

### C++ domain core (`cpp_core/`)

| Type | Role |
|------|------|
| `MimeContent` | Typed body (`text/plain` or `text/html`); factories `PlainText` / `Html` |
| `Mailcart` | Base message: normalized sender, recipient, subject, MIME body |
| `OutlookMailcart` | Graph-enriched message: `messageId`, `receivedAt`, body text/html, attachments |
| `OutlookMailcartSummary` | Lightweight search row: id, subject, preview, `receivedAt` |
| `OutlookSearchResult` | Summaries + `nextCursor` + `errorMessage` |
| `OutlookClient` | Orchestrates the gateway + parser for search and read |
| `OutlookServiceGateway` | Virtual: fetch raw JSON payloads (implemented in the bridge) |
| `OutlookPayloadParser` | Virtual: parse JSON into domain objects (implemented in the bridge) |

### Bridge (`macos_app/Bridge/`)

Objective-C++ layer connecting Swift to the C++ core. It exposes `searchMailcartsWithQuery:limit:cursor:`,
`readMailcartWithMessageId:`, and `moveMessageToFolder:` to Swift, performs synchronous Graph HTTP, and on a
`401` spawns the `cpp_core/build/mailcart_token --force` binary (overridable via `MAILCART_TOKEN_BIN`) and
retries once. Token is resolved from `~/.cache/mailcart/graph_oauth.json` or the `OUTLOOK_GRAPH_TOKEN`
environment variable. Immutable Objective-C DTOs isolate Swift from C++/Graph details.

### Swift UI (`macos_app/UI/`)

`OutlookMailApp` is the `@main` entry that starts `CrashReporterService` (PLCrashReporter). `OutlookMailViewModel`
is a `@MainActor` state holder that debounces search, paginates, and dispatches bridge calls on a background
queue. `UITestingSupport` injects deterministic fixture data under `--ui-testing` / `MAILCART_UI_TEST_MODE=1`.

## HTTPS API path (`scripts/`)

`matchy_mailcart_api.py` exposes the upstream message contract and uses the `requests` library against Graph.
Both surfaces share the same `GraphTokenManager` and on-disk token cache.

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | Liveness |
| `GET /v1/messages/search?query=<string>&limit=<1-100>` | Scoped search; returns `messages[]` |
| `GET /v1/messages/{message_id}` | Full message (html/text body, recipients) |
| `POST /v1/messages/{message_id}/move` | Move to a folder, e.g. `{"folder_name": "matchy"}` |

Search responses always include a `messages` array (a legacy `items` array is accepted by consumers as a
fallback). Date-bounded searches follow Graph `@odata.nextLink` pagination.

## OAuth Token Model

```text
1Password (OUTLOOK_GRAPH_API item: token / refresh_token / application_client_id)
   -> 1psa
   -> GraphTokenManager bootstrap
   -> ~/.cache/mailcart/graph_oauth.json (mode 600)
   -> Authorization: Bearer <token> on Graph calls
   -> 401 -> invalidate -> refresh at Microsoft token endpoint -> persist -> retry once
```

Microsoft Graph delegated scopes: `Mail.Read` (search/read) and `Mail.ReadWrite` (move matched messages to the
`matchy` folder). The `mailcart_token` CLI (built from `cpp_core/`, a port of the retired
`scripts/refresh_graph_token.py`) warms the shared cache and is invoked by `make run-api` and the bridge's 401
handler.

## C++ migration status (Python -> C++)

The Graph integration is being migrated from Python to the portable `cpp_core/` C++20 core, following the
classy/teller family pattern:

- `cpp_core/src/token.cpp` (+ `mailcart_token` CLI) ports `scripts/graph_token.py` and
  `scripts/refresh_graph_token.py`. The bridge 401 handler and `make run-api` now use the C++ binary.
- `cpp_core/src/{search,graph,api}.cpp` (+ the `mailcart_api` HTTPS server, built with cpp-httplib/OpenSSL) port
  the scoped search, Graph client, and endpoint layer of `scripts/matchy_mailcart_api.py`, preserving the
  `/v1/messages/*` contract, status codes, and JSON envelopes. `make run-api` serves via `mailcart_api`.
- `cpp_core/openapi/openapi.json` is the frozen FastAPI contract export retained for the DAST/Schemathesis lane.
- `cpp_core/oracle/` holds the parity harness: `compare_oracle.py` drives the same `scenarios.json` through the
  FastAPI reference app and the C++ `mailcart_oracle_runner` and diffs them; `goldens.json` is the frozen result
  that the C++ runner replays after the Python reference is retired (`make parity`).
- The Python sources remain as the parity oracle until the t06/t07/t10/t11 lanes, the runner profile, and CI are
  cut over to the C++ lanes (t17 unit, t18 sanitizer, t19 parity, t20 fuzz).

## Search Algorithm: Aho-Corasick

A single `/v1/messages/search` query can carry several scoped filters (`subject:`, `sender:`, `body:`, `from:`,
`to:`) combined with AND semantics. Rather than scanning each field once per filter, `AhoCorasick` and
`_build_criteria_matcher` in `scripts/matchy_mailcart_api.py` build one automaton (a trie of all filter strings
plus failure links) and find every matching filter in a single O(text + patterns) pass. The automaton is built
once per request and reused across every scanned message (`R050`).

The macOS bridge uses a simpler case-insensitive subject/preview contains filter; the rich scoped search lives
only in the HTTPS API.

## Build and Quality Gates

The `Makefile` is the primary developer interface; numbered scripts are thin runner pointers.

| Target | What it does |
|--------|--------------|
| `make build` | Bridge compile check + Swift typecheck + Xcode app build |
| `make test` | C++ Catch2 unit suite + oracle parity replay + Python unittest + Bats shell tests |
| `make core` / `core-test` | Configure/build `mailcartcore` + tools; run the Catch2 suite via ctest |
| `make sanitize` | Catch2 suite under ASan+UBSan in a separate `build-asan/` tree |
| `make parity` | Replay `cpp_core/oracle/goldens.json` through the C++ API handlers |
| `make fuzz` | Build/run the libFuzzer targets (query parse, Aho-Corasick, Graph payloads) via brew LLVM |
| `make ui-test` | Inline UI regression + XCUITest suite + smoke launch (optional crash-reporter smoke) |
| `make sast` | ShellCheck, Semgrep, Bandit, detect-secrets, gitleaks |
| `make lint` | clang-tidy (C++/ObjC++), SwiftLint, Ruff (all blocking) |
| `make clam` | ClamAV recursive scan |
| `make run` | Build app, refresh token, read 1psa token, launch macOS app |
| `make run-api` | Refresh token (`mailcart_token`), ensure TLS, start the C++ `mailcart_api` HTTPS server on 8788 |

Numbered runbook scripts (`01`-`06`) and `tests/tNN_*` lanes are thin pointers that set
`RUNBOOK_REPO_ROOT`, source `runner/config/runbook/mailcart.env`, and exec the corresponding golden in
[`../runner/`](../runner/). `05_install_matchy_api_tls.sh` generates local TLS material for the HTTPS API, and
`06_run_all_tests_parallel.sh` delegates to the runner's parallel orchestrator golden.

## Requirements Traceability

Every module and script has a matching spec under `requirements/` following a Statement -> Design -> Tests
shape, with `#R###` anchors embedded in source (for example `#R020` in `matchy_mailcart_api.py`, `#R050` in the
search matcher). The traceability lane verifies that requirements, source tags, and tests stay in sync.

## Languages and Frameworks

| Layer | Stack |
|-------|-------|
| Domain core | C++20 (`cpp_core/`: CMake + FetchContent for nlohmann/json, cpp-httplib, Catch2); legacy C++17 model types |
| Bridge | Objective-C / Objective-C++ (Graph HTTP, JSON) |
| UI | Swift / SwiftUI (macOS 13+), XCUITest; project from `macos_app/project.yml` via XcodeGen |
| API | C++ `mailcart_api` (cpp-httplib + OpenSSL); Python 3 (FastAPI) retained as the parity oracle pending retirement |
| Tooling | Make, BATS, ShellCheck, Semgrep, Bandit, detect-secrets, gitleaks, clang-tidy, SwiftLint, Ruff, ClamAV |
| Crash reporting | PLCrashReporter (SPM) |
