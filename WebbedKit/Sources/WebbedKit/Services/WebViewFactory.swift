import Foundation
import WebKit

// MARK: - WebViewFactory

/// Single point of construction for `WKWebView` instances. Centralised so
/// the configuration (process pool, data store, preferences) stays consistent
/// across macOS and iOS.
@MainActor
public enum WebViewFactory {

    /// Build a configured `WKWebView` ready to host a tab.
    public static func make() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        #if os(macOS)
        webView.allowsMagnification = true
        #endif
        return webView
    }

    /// Convenience: build and load if the tab has a URL, otherwise return a
    /// blank web view.
    public static func make(for tab: TabRecord) -> WKWebView {
        let wv = make()
        if let url = tab.url {
            wv.load(URLRequest(url: url))
        }
        return wv
    }
}
