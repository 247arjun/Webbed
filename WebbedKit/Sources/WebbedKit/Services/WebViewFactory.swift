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

    // MARK: - User scripts

    /// User script that watches `<meta name="theme-color">` and reports
    /// the live value back to a `themeColor` message handler. The mutation
    /// observer keeps it fresh across SPA route changes.
    public static let themeColorUserScript: WKUserScript = {
        let source = #"""
        (function() {
            function read() {
                var m = document.querySelector('meta[name="theme-color"]');
                var v = m ? m.getAttribute('content') : null;
                try { window.webkit.messageHandlers.themeColor.postMessage(v || ""); } catch (e) {}
            }
            read();
            if (document.head) {
                var observer = new MutationObserver(read);
                observer.observe(document.head, { childList: true, subtree: true, attributes: true });
            }
            document.addEventListener('DOMContentLoaded', read);
        })();
        """#
        return WKUserScript(source: source,
                            injectionTime: .atDocumentEnd,
                            forMainFrameOnly: true)
    }()

    /// Favicon user script — picks the largest `<link rel="icon">` and
    /// reports the href to a `favicon` message handler.
    public static let faviconUserScript: WKUserScript = {
        let source = #"""
        (function() {
            function bestIcon() {
                var links = document.querySelectorAll('link[rel~="icon"]');
                if (links.length === 0) return null;
                var best = null, bestSize = 0;
                for (var i = 0; i < links.length; i++) {
                    var l = links[i];
                    var sizesAttr = (l.getAttribute('sizes') || '').toLowerCase();
                    var sz = 0;
                    if (sizesAttr === 'any') { sz = 9999; }
                    else { var m = sizesAttr.match(/(\d+)x\d+/); if (m) sz = parseInt(m[1], 10); }
                    if (best === null || sz > bestSize) { best = l; bestSize = sz; }
                }
                return best ? best.href : null;
            }
            function report() {
                var href = bestIcon();
                if (href) {
                    try { window.webkit.messageHandlers.favicon.postMessage(href); } catch (e) {}
                }
            }
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', report);
            } else {
                report();
            }
        })();
        """#
        return WKUserScript(source: source,
                            injectionTime: .atDocumentEnd,
                            forMainFrameOnly: true)
    }()
}
