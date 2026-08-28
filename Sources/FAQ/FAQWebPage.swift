// NuDefndr — nudefndr.com
// Transparency Repository - In-app FAQ renderer (v2.6.1)

import SwiftUI
import WebKit

/// The renderer for a `FAQDocument`, and nothing else.
///
/// It is handed a finished string with `baseURL: nil`, so there is no origin to
/// resolve a relative URL against and no subresource left to fetch — the page is
/// already whole. Every network switch below is therefore belt and braces rather
/// than the thing keeping the promise, and that is deliberate: the promise is
/// kept by the fetch happening in `FAQDocumentStore`, where it can be described.
///
/// - `nonPersistent()` — no cookie jar, no local storage, no disk cache. Nothing
///   about this screen survives it being closed.
/// - the navigation delegate cancels every navigation except the initial load,
///   so a link cannot walk the user out of the FAQ and into the rest of the site
///   or, worse, out to Safari.
struct FAQWebPage: UIViewRepresentable {
    let html: String
    /// Painted behind the page so a slow first paint is the app's colour rather
    /// than the white a `WKWebView` defaults to.
    let background: Color

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true   // the accordions
        config.allowsInlineMediaPlayback = false
        config.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(background)
        webView.scrollView.backgroundColor = UIColor(background)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Pinch-zooming a page of body text inside a sheet only ever happens by
        // accident, and it leaves the FAQ scrolled sideways with no way back.
        webView.scrollView.bouncesZoom = false
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.backgroundColor = UIColor(background)
        webView.scrollView.backgroundColor = UIColor(background)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(html: html) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String

        init(html: String) { self.loadedHTML = html }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // `.other` is the `loadHTMLString` itself. Anything the user or the
            // page initiates — a link, a form, a redirect — is refused.
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}
