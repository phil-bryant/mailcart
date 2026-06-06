# MailcartUITests Requirements

## Scope

Applies to `macos_app/UITests/MailcartUITests.swift`.

R001  Statement: Declare the automated end-to-end mailbox regression suite that drives the packaged app.
Design: `MailcartUITests` subclasses `XCTestCase`, launches `XCUIApplication` with the `--ui-testing` argument and fixture environment in `setUpWithError`, and exposes `test*` cases that exercise search, pagination, selection, and body-mode flows.
Tests:
- R001-T01: `MailcartUITests` launches the fixture app and declares the search/pagination/detail regression cases.

## Changelog

- 2026-06-06: Initial requirements doc covering `macos_app/UITests/MailcartUITests.swift` end-to-end suite entrypoints.
