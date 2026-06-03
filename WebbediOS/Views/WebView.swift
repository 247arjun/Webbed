import SwiftUI
import WebKit
import WebbedKit

// MARK: - WebView

/// SwiftUI wrapper around `WKWebView`. Mirrors the shape of Noted's
/// `RichTextEditor` (UIViewRepresentable) but hosts a browser engine.
struct WebView: UIViewRepresentable {

    let tabID: UUID
    @Binding var url: URL?
    @Binding var title: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    /// Set to a non-nil value to request an action; coordinator resets to nil
    /// after performing it.
    @Binding var pendingAction: WebAction?

    func makeUIView(context: Context) -> WKWebView {
        let webView = WebViewFactory.make()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate         = context.coordinator
        context.coordinator.attachKVO(to: webView)
        context.coordinator.webView = webView
        if let url { webView.load(URLRequest(url: url)) }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Apply pending action (Back/Forward/Reload/Stop/Load).
        if let action = pendingAction {
            switch action {
            case .back:    webView.goBack()
            case .forward: webView.goForward()
            case .reload:  webView.reload()
            case .stop:    webView.stopLoading()
            case .load(let u): webView.load(URLRequest(url: u))
            }
            DispatchQueue.main.async { pendingAction = nil }
        }

        // External URL change → load it.
        if let want = url, webView.url != want, !webView.isLoading {
            // Avoid reloading on every state churn — only when truly different.
            if webView.url?.absoluteString != want.absoluteString {
                webView.load(URLRequest(url: want))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebView
        weak var webView: WKWebView?
        private var observers: [NSKeyValueObservation] = []

        init(parent: WebView) { self.parent = parent }

        deinit { observers.forEach { $0.invalidate() } }

        func attachKVO(to wv: WKWebView) {
            observers.append(wv.observe(\.title, options: [.new]) { [weak self] _, change in
                let t = change.newValue?.flatMap { $0 } ?? ""
                Task { @MainActor in self?.parent.title = t }
            })
            observers.append(wv.observe(\.url, options: [.new]) { [weak self] _, change in
                let u = change.newValue.flatMap { $0 }
                Task { @MainActor in self?.parent.url = u }
            })
            observers.append(wv.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
                let v = change.newValue ?? false
                Task { @MainActor in self?.parent.canGoBack = v }
            })
            observers.append(wv.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
                let v = change.newValue ?? false
                Task { @MainActor in self?.parent.canGoForward = v }
            })
            observers.append(wv.observe(\.isLoading, options: [.new]) { [weak self] _, change in
                let v = change.newValue ?? false
                Task { @MainActor in self?.parent.isLoading = v }
            })
            observers.append(wv.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                let v = change.newValue ?? 0
                Task { @MainActor in self?.parent.estimatedProgress = v }
            })
        }

        // WKUIDelegate — open popups by loading inline.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

// MARK: - WebAction

enum WebAction: Equatable {
    case back, forward, reload, stop, load(URL)
}
