# UITestingSupport Requirements

## Scope

Applies to `macos_app/UI/UITestingSupport.swift`.

R001  Statement: Select an in-memory fixture bridge when the app launches in automated fixture mode.
Design: `buildDefaultOutlookBridgeClient` dispatches by launch mode and returns a `UITestingFixtureBridge` for fixture mode and `OutlookClientBridge` otherwise.
Tests:
- R001-T01: Launch-mode detection and the bridge factory route fixture-mode launches to the fixture bridge.

R005  Statement: Provide deterministic paginated mailcart fixtures for automated regression runs.
Design: `UITestingFixtureBridge` implements `OutlookBridgeClient` over in-memory fixture records, filtering by query and returning cursor-paged summaries from `searchMailcarts`.
Tests:
- R005-T01: `UITestingFixtureBridge` searches in-memory fixtures and returns cursor-paged summaries.

## Changelog

- 2026-06-06: Initial requirements doc covering `macos_app/UI/UITestingSupport.swift` launch-mode detection and fixture bridge.
