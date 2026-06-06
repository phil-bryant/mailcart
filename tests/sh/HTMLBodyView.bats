#!/usr/bin/env bats

# Interface contract checks for the macOS HTML body rendering view.

load helpers/repo_root

setup() {
  #R001: Test harness setup for HTMLBodyView contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/macos_app/UI/HTMLBodyView.swift"
}

@test "R001: HTMLBodyView renders wrapped HTML in a WKWebView" {
  #R001-T01: HTMLBodyView is an NSViewRepresentable that loads wrapped HTML into a WKWebView.
  run rg -F "struct HTMLBodyView: NSViewRepresentable {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "func makeNSView(context: Context) -> WKWebView {" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "webView.loadHTMLString(wrappedHTML(html), baseURL: nil)" "${SRC}"
  [ "$status" -eq 0 ]
}
