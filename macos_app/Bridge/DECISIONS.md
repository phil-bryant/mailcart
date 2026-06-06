# Bridge decomposition decision — `OutlookClientBridge.mm`

## Status: DONE (2026-06-05)

`macos_app/Bridge/OutlookClientBridge.mm` was the named maintainability bottleneck (re-rating Item 5): a ~1,025-line
Objective-C++ monolith mixing Graph HTTP, JSON conversion, payload parsing, folder/move, and the ObjC↔C++ bridge. It
has now been decomposed into cohesive single-responsibility translation units behind the existing gateway/parser seams,
**preserving the public ObjC++ interface (`OutlookClientBridge`) and behavior**. The earlier deferral was unblocked by
splitting the requirements doc and the gate tests in lockstep with the code, plus the build wiring.

## New unit breakdown

| Unit (`.h`/`.mm`)              | Responsibility                                                        | Owns `#R` |
|--------------------------------|-----------------------------------------------------------------------|-----------|
| `OutlookGraphConversions`      | `std::string`↔`NSString` conversion + shared JSON normalization       | R010      |
| `OutlookGraphHttpClient`       | Graph token resolution, GET transport, search/message/attachment builders | R015, R020, R025, R030 |
| `OutlookGraphMessageMover`     | POST transport, typed request structs, folder-ensure + move-to-folder | R050      |
| `OutlookBridgeParser`          | Graph JSON → `OutlookJsonObject` payload parsing                      | R035      |
| `OutlookClientBridge` (core)   | Gateway adapter + ObjC bridge class + C++ client lifecycle            | R001, R040, R045 |
| `OutlookBridgeModels` (`.h`/`.m`) | Immutable DTO models (unchanged behavior; tags trimmed to owner)   | R005      |

`OutlookClientBridge.mm` shrank from ~1,025 lines to ~190 lines (gateway adapter + the ObjC class that marshals to/from
the C++ `OutlookClient` and delegates Graph work to the sibling units). Function bodies were relocated verbatim to
preserve behavior; the cross-unit helpers moved from a single anonymous namespace into a shared `mailcart_bridge`
namespace declared in the new headers.

## How the prior blockers were resolved

1. **Traceability contract (t04).** The monolithic `Bridge-requirements.md` (which pinned all 11 IDs to every Bridge
   file) was replaced by six per-unit `*-requirements.md` docs. Each `#R` tag now lives with the code that owns the
   behavior, and each doc's scoped source files carry exactly that doc's ID set. t04 passes (`requirements ↔ #R tags ↔
   tagged tests`) for all six units.
2. **Source-anchored Bats (t05).** The single `tests/sh/Bridge.bats` was replaced by six per-unit Bats files
   (`OutlookClientBridge.bats`, `OutlookBridgeModels.bats`, `OutlookGraphConversions.bats`, `OutlookGraphHttpClient.bats`,
   `OutlookGraphMessageMover.bats`, `OutlookBridgeParser.bats`). Each contract assertion now anchors to the new file that
   owns the symbol/signature; every assertion stays real (source-contract `rg` idiom) and keeps its `#R` tag.
3. **Build wiring (t09).** `macos_app/project.yml` globs the whole `Bridge/` directory, so the new `.mm`/`.h` files are
   compiled and linked by the app target automatically. The Makefile's standalone `_bridge-check` and the blocking
   `_sast_clang_tidy` lane were updated to compile/analyze each new translation unit, and `_ui-build`'s staleness list
   now includes them. The new units keep the typed-struct pattern so `bugprone-easily-swappable-parameters` stays clean.

## Verification scope (what was vs was not verified)

- Verified green: `t04` (traceability), `t05` (Bridge Bats lane), `t09` (`make build` Swift/ObjC++ compile + link,
  clang-tidy, SwiftLint), plus `t08` (C++ integration) and `t06` (Python) as unaffected lanes.
- **Not verified:** runtime/behavioral correctness against live Microsoft Graph. The bridge still has no automated
  runtime/behavioral harness — only the running macOS app exercises the live Graph seam. The decomposition relocates
  function bodies verbatim and preserves the public interface, but a live-token smoke run was not performed here.

## Style note

Relocated function bodies retain the original control-flow shape (early returns / `break` inside fetch-retry loops) to
preserve behavior exactly rather than rewrite an untested live-integration seam to satisfy the single-return /
structured-control-flow style rules. New scaffolding (headers, namespaces, includes) follows the house style. The
typed request structs (`GraphRequestHeaders`, `MoveMessageRequest`) are intentionally retained as `struct` because R050
and the clang-tidy swappable-parameter policy mandate them.
