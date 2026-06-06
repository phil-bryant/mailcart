# HTMLBodyView Requirements

## Scope

Applies to `macos_app/UI/HTMLBodyView.swift`.

R001  Statement: Render HTML message bodies inside an embedded web view.
Design: `HTMLBodyView` is a SwiftUI `NSViewRepresentable` that builds a `WKWebView`, wraps the supplied HTML in a styled document, and reloads it via `loadHTMLString` only when the html content changes.
Tests:
- R001-T01: `HTMLBodyView` is an `NSViewRepresentable` that loads wrapped HTML into a `WKWebView`.

## Changelog

- 2026-06-06: Initial requirements doc covering `macos_app/UI/HTMLBodyView.swift` HTML body rendering.
