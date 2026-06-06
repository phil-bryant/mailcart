# MailcartLaunchMode Requirements

## Scope

Applies to `macos_app/UI/MailcartLaunchMode.swift`.

R001  Statement: Detect fixture launch mode from process arguments and environment.
Design: `detectMailcartLaunchMode(arguments:environment:)` returns `.uiTesting` when `--ui-testing` is present or `MAILCART_UI_TEST_MODE=1`, otherwise `.normal`; `detectMailcartLaunchMode(processInfo:)` delegates to this deterministic helper.
Tests:
- R001-T01: launch-mode helper inspects args/env and exposes a ProcessInfo wrapper.

## Changelog

- 2026-06-06: Initial requirements doc for launch-mode detection helpers.
