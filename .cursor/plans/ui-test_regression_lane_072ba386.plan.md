---
name: ui-test regression lane
overview: Refactor test lane responsibilities so `make test` owns all BATS execution while `make ui-test` runs a non-BATS multi-check UI regression lane plus smoke launch verification.
todos:
  - id: makefile-lane-refactor
    content: "Refactor Makefile targets: move BATS responsibility to `make test`, add `_ui-regression`, and wire `ui-test` to regression + smoke lanes"
    status: completed
  - id: makefile-bats-update
    content: Update `tests/sh/Makefile.bats` assertions for new `test`/`ui-test` contracts
    status: completed
  - id: requirements-sync
    content: Update `requirements/Makefile-requirements.md` for revised R005/R035 behavior and changelog
    status: completed
  - id: validate-lanes
    content: Run `make test`, `make ui-test`, and `bats tests/sh/Makefile.bats` to verify behavior
    status: completed
isProject: false
---

# Move UI Regression Into `make ui-test`

## Goal
Align target intent so `make test` is the BATS runner, and `make ui-test` performs several inline UI regression checks (non-BATS) plus smoke launch validation.

## Proposed Changes
- Update [`/Users/phil/local/src/mailcart/Makefile`](/Users/phil/local/src/mailcart/Makefile):
  - Make `test` run C++ integration + full shell BATS suite (including `tests/sh/UI.bats`).
  - Remove `bats tests/sh/UI.bats` execution from `ui-test`.
  - Add a new internal `_ui-regression` target (implemented directly in `Makefile`, no separate script) that runs multiple `rg`-based assertions across UI files, covering key invariants currently guarded by UI checks (for example: load-more copy, rendered/raw body mode wiring, bridge off-main execution).
  - Have `ui-test` call `_ui-regression` and `_ui-smoke` (with existing crash-reporter toggle behavior preserved).
  - Update help text/comments to reflect the new lane contract.

- Update [`/Users/phil/local/src/mailcart/tests/sh/Makefile.bats`](/Users/phil/local/src/mailcart/tests/sh/Makefile.bats):
  - Adjust the `R005` test to expect `make test` runs all BATS files (including `UI.bats`).
  - Rewrite `R035` expectations so `make ui-test` verifies inline regression lane output and smoke behavior, and no longer expects a `bats tests/sh/UI.bats` invocation.
  - Keep crash toggle assertions (`R080`) aligned with the new `ui-test` flow.

- Update [`/Users/phil/local/src/mailcart/requirements/Makefile-requirements.md`](/Users/phil/local/src/mailcart/requirements/Makefile-requirements.md):
  - Revise `R005`/`R035` design + tests to encode the new division of responsibilities.
  - Add changelog entry documenting the contract shift from UI BATS-in-`ui-test` to inline regression checks in `ui-test`.

## Regression Checks To Inline In `Makefile`
- Validate load-more button wording contract in `OutlookMailContentView`.
- Validate rendered-vs-raw mode wiring and `HTMLBodyView` usage/import.
- Validate view-model bridge operations remain off main actor queue.
- Add 1-2 additional high-signal UI structure checks (for example `NavigationSplitView` + search placeholder binding) so `ui-test` runs “several” regressions before smoke.

## Verification
- Run `make test` and confirm BATS execution includes `tests/sh/UI.bats`.
- Run `make ui-test` and confirm:
  - inline regression checks execute and fail fast on mismatch,
  - smoke launch still executes and preserves current failure semantics,
  - crash reporter smoke remains opt-in via `RUN_CRASH_REPORTER_SMOKE_TEST=true`.
- Run `bats tests/sh/Makefile.bats` to confirm test harness expectations match new target behavior.