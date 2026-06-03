import SwiftUI
import WebKit
import WebbedKit
import CryptoKit

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
        let host = url?.host
        let store = AppModel.shared.permissionStore
        let autoplay = store.decision(for: host, kind: .autoplay) == .allow
        let popups   = store.decision(for: host, kind: .popups)   == .allow
        let webView = WebViewFactory.make(autoplayAllowed: autoplay, popupsAllowed: popups)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate         = context.coordinator
        context.coordinator.installFaviconScript(on: webView)
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebView
        weak var webView: WKWebView?
        private var observers: [NSKeyValueObservation] = []
        private var snapshotWorkItem: DispatchWorkItem?

        init(parent: WebView) { self.parent = parent }

        deinit {
            observers.forEach { $0.invalidate() }
        }

        func installFaviconScript(on webView: WKWebView) {
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
                    if (href) { window.webkit.messageHandlers.favicon.postMessage(href); }
                }
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', report);
                } else {
                    report();
                }
            })();
            """#
            let script = WKUserScript(source: source,
                                      injectionTime: .atDocumentEnd,
                                      forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(script)
            webView.configuration.userContentController.add(self, name: "favicon")
        }

        nonisolated func userContentController(_ userContentController: WKUserContentController,
                                               didReceive message: WKScriptMessage) {
            Task { @MainActor in
                guard message.name == "favicon",
                      let href = message.body as? String,
                      let url = URL(string: href) else { return }
                let tabID = self.parent.tabID
                if let ref = await FaviconCache.shared.fetch(iconURL: url) {
                    AppModel.shared.tabStore.updateFaviconRef(tabID: tabID, ref: ref)
                }
            }
        }

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

        // WKUIDelegate — popup intercept consults permission store.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            let host = navigationAction.sourceFrame.request.url?.host ?? webView.url?.host
            if AppModel.shared.permissionStore.decision(for: host, kind: .popups) == .deny {
                return nil
            }
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        // WKUIDelegate — camera / mic capture consults the store.
        func webView(_ webView: WKWebView,
                     decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                     initiatedBy frame: WKFrameInfo,
                     type: WKMediaCaptureType) async -> WKPermissionDecision {
            let host = origin.host
            let kinds: [PermissionKind] = {
                switch type {
                case .camera:              return [.camera]
                case .microphone:          return [.microphone]
                case .cameraAndMicrophone: return [.camera, .microphone]
                @unknown default:          return [.camera]
                }
            }()
            let store = AppModel.shared.permissionStore
            var anyDeny = false; var allAllow = true
            for kind in kinds {
                let d = store.decision(for: host, kind: kind)
                if d == .deny  { anyDeny = true }
                if d != .allow { allAllow = false }
            }
            if anyDeny  { return .deny }
            if allAllow { return .grant }
            return .prompt
        }

        // WKNavigationDelegate — per-origin gates (JS, mixed content,
        // open-in-external).
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
            let url  = navigationAction.request.url
            let host = url?.host
            let store = AppModel.shared.permissionStore

            // 1. Open-in-external (main frame, same host as click target).
            if navigationAction.targetFrame?.isMainFrame == true,
               let host, let url,
               store.decision(for: host, kind: .openInExternal) == .allow,
               url.host == host {
                await MainActor.run { UIApplication.shared.open(url) }
                return (.cancel, preferences)
            }

            // 2. Block insecure subresources unless allowed.
            if let url, url.scheme == "http",
               let main = webView.url, main.scheme == "https",
               navigationAction.targetFrame?.isMainFrame != true,
               store.decision(for: main.host, kind: .insecureContent) != .allow {
                return (.cancel, preferences)
            }

            // 3. Per-origin JavaScript gate.
            preferences.allowsContentJavaScript = store.decision(for: host, kind: .javascript) != .deny
            return (.allow, preferences)
        }

        // WKNavigationDelegate — debounced snapshot capture (mirrors macOS).
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            snapshotWorkItem?.cancel()
            let tabID = parent.tabID
            let work = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else { return }
                Task { @MainActor in self.captureSnapshot(webView: webView, tabID: tabID) }
            }
            snapshotWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }

        @MainActor
        private func captureSnapshot(webView: WKWebView, tabID: UUID) {
            guard AppSettings.shared.syncTabPreviews else { return }
            let config = WKSnapshotConfiguration()
            config.afterScreenUpdates = true
            webView.takeSnapshot(with: config) { image, error in
                guard let image else {
                    if let error { Log.web.debug("Snapshot failed: \(error.localizedDescription)") }
                    return
                }
                Task { @MainActor in
                    guard let png = Self.pngData(from: image, maxBytes: 80 * 1024) else { return }
                    let ref = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                    let store = AppModel.shared.tabStore
                    do {
                        try store.persistenceService.saveSnapshot(tabID: tabID, pngData: png)
                        store.updateSnapshotRef(tabID: tabID, ref: ref)
                    } catch {
                        Log.persist.error("Snapshot save failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        /// Downscale + PNG-encode a UIImage, retrying smaller widths until under
        /// `maxBytes`. Returns nil if we can't get under the cap.
        private static func pngData(from image: UIImage, maxBytes: Int) -> Data? {
            let targetWidths: [CGFloat] = [800, 600, 480, 360, 280]
            for w in targetWidths {
                guard let resized = resize(image, toWidth: w),
                      let png = resized.pngData() else { continue }
                if png.count <= maxBytes { return png }
            }
            return nil
        }

        private static func resize(_ image: UIImage, toWidth width: CGFloat) -> UIImage? {
            let aspect = image.size.height / max(image.size.width, 1)
            let size = CGSize(width: width, height: width * aspect)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }
}

// MARK: - WebAction

enum WebAction: Equatable {
    case back, forward, reload, stop, load(URL)
}
