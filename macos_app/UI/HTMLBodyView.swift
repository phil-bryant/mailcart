import SwiftUI
import WebKit

// #R001: HTMLBodyView is an NSViewRepresentable that renders message HTML in a WKWebView.
struct HTMLBodyView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(wrappedHTML(html), baseURL: nil)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            nsView.loadHTMLString(wrappedHTML(html), baseURL: nil)
            context.coordinator.lastHTML = html
        }
    }

    private func wrappedHTML(_ body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0" />
            <style>
                :root { color-scheme: light dark; }
                body {
                    margin: 0;
                    padding: 0;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                    font-size: 14px;
                    line-height: 1.45;
                    overflow-wrap: break-word;
                }
                img { max-width: 100%; height: auto; }
                table { max-width: 100%; }
                pre { white-space: pre-wrap; }
            </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String = ""
    }
}
