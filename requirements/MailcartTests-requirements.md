# MailcartTests Requirements

## Scope

Applies to `macos_app/Tests/MailcartTests.swift`.

R001  Statement: Declare the automated macOS Swift unit-test suite baseline.
Design: `MailcartTests` subclasses `XCTestCase` and validates launch-mode detection behavior so `--ui-testing` and `MAILCART_UI_TEST_MODE=1` resolve to `.uiTesting`, while default launches remain `.normal`.
Tests:
- R001-T01: `MailcartTests` declares launch-mode behavior XCTest cases.

## Changelog

- 2026-06-06: Initial requirements doc covering `macos_app/Tests/MailcartTests.swift` unit-test suite entrypoints.
