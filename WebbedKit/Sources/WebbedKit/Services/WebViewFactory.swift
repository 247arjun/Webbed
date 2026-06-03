import Foundation
import WebKit

// MARK: - WebViewFactory

/// Single point of construction for `WKWebView` instances. Centralised so
/// the configuration (process pool, data store, preferences) stays consistent
/// across macOS and iOS.
@MainActor
public enum WebViewFactory {

    /// Build a configured `WKWebView` ready to host a tab.
    /// - Parameters:
    ///   - autoplayAllowed: when false (default), media requires a user
    ///     gesture before playing. Flip on for origins that have an
    ///     `.allow` autoplay grant.
    ///   - popupsAllowed: lets JavaScript open child windows without a
    ///     user click. Off by default; flip per-origin via permissions.
    public static func make(autoplayAllowed: Bool = false,
                            popupsAllowed: Bool = false) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = autoplayAllowed ? [] : .all
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = popupsAllowed

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
    public static func make(for tab: TabRecord,
                            autoplayAllowed: Bool = false,
                            popupsAllowed: Bool = false) -> WKWebView {
        let wv = make(autoplayAllowed: autoplayAllowed, popupsAllowed: popupsAllowed)
        if let url = tab.url {
            wv.load(URLRequest(url: url))
        }
        return wv
    }
}
