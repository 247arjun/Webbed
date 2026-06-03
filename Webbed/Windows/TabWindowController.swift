import AppKit
import WebKit
import WebbedKit

// MARK: - TabWindowController

/// Manages one tab window. Coordinates the content view, WKWebView KVO, and
/// the TabStore.
@MainActor
final class TabWindowController: NSWindowController,
                                 NSWindowDelegate,
                                 TabContentViewDelegate,
                                 WKNavigationDelegate,
                                 WKUIDelegate {

    let tabID: UUID
    private weak var tabStore: TabStore?
    private(set) var contentView: TabContentView
    private var kvoObservers: [NSKeyValueObservation] = []
    private var snapshotWorkItem: DispatchWorkItem?

    // MARK: - Init

    init(tabID: UUID, tabStore: TabStore, frame: NSRect, theme: WebbedTheme) {
        self.tabID = tabID
        self.tabStore = tabStore

        let webView = WebViewFactory.make()
        contentView = TabContentView(tabID: tabID, theme: theme, webView: webView)

        let window = TabWindow(contentRect: frame)
        window.contentView = contentView
        contentView.frame = window.contentView!.bounds
        contentView.autoresizingMask = [.width, .height]

        super.init(window: window)

        window.delegate = self
        contentView.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self

        installKVO(on: webView)
        contentView.applyResponsiveLayout(for: frame.size)
        Log.window.debug("Created window controller for tab \(tabID, privacy: .public)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        kvoObservers.forEach { $0.invalidate() }
    }

    // MARK: - Public

    func loadContent(from tab: TabRecord) {
        contentView.updateAddress(tab.displayURLString)
        contentView.updatePinState(tab.isPinned)
        applyPinLevel(tab.isPinned)
        if let url = tab.url {
            contentView.webView.load(URLRequest(url: url))
        } else if let home = AppSettings.shared.homepageURL {
            contentView.webView.load(URLRequest(url: home))
        }
    }

    func applyTheme(_ theme: WebbedTheme) {
        contentView.applyTheme(theme)
    }

    /// Called by ResizeHandleView on mouseUp.
    func windowDidEndResize() {
        persistFrame()
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    func windowDidResize(_ notification: Notification) {
        guard let frame = window?.frame else { return }
        contentView.applyResponsiveLayout(for: frame.size)
        persistFrame()
    }

    func windowWillClose(_ notification: Notification) {
        tabStore?.markClosed(tabID: tabID, isClosed: true)
        NotificationCenter.default.post(name: .tabWindowDidClose, object: tabID)
        Log.window.debug("Window closed for tab \(self.tabID, privacy: .public)")
    }

    // MARK: - KVO

    private func installKVO(on webView: WKWebView) {
        kvoObservers.append(webView.observe(\.title, options: [.new]) { [weak self] _, change in
            Task { @MainActor in
                guard let self else { return }
                self.tabStore?.updateTitle(tabID: self.tabID, title: change.newValue?.flatMap { $0 } ?? "")
            }
        })

        kvoObservers.append(webView.observe(\.url, options: [.new]) { [weak self] _, change in
            Task { @MainActor in
                guard let self else { return }
                let url = change.newValue.flatMap { $0 }
                self.tabStore?.updateURL(tabID: self.tabID, url: url)
                self.contentView.updateAddress(url?.absoluteString ?? "")
            }
        })

        kvoObservers.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
            let p = change.newValue ?? 0
            Task { @MainActor in
                guard let self else { return }
                self.contentView.updateProgress(p, isLoading: self.contentView.webView.isLoading)
            }
        })

        kvoObservers.append(webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
            let loading = change.newValue ?? false
            Task { @MainActor in
                guard let self else { return }
                self.contentView.updateProgress(self.contentView.webView.estimatedProgress, isLoading: loading)
            }
        })

        kvoObservers.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
            let canBack = change.newValue ?? false
            Task { @MainActor in
                guard let self else { return }
                self.contentView.updateNavButtons(canGoBack: canBack, canGoForward: self.contentView.webView.canGoForward)
            }
        })

        kvoObservers.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] _, change in
            let canFwd = change.newValue ?? false
            Task { @MainActor in
                guard let self else { return }
                self.contentView.updateNavButtons(canGoBack: self.contentView.webView.canGoBack, canGoForward: canFwd)
            }
        })
    }

    // MARK: - TabContentViewDelegate

    func tabContentView(_ view: TabContentView, didSubmitAddress text: String) {
        guard let url = URLHeuristics.resolve(text, using: AppSettings.shared.searchProvider) else { return }
        view.webView.load(URLRequest(url: url))
    }

    func tabContentViewDidClickBack(_ view: TabContentView)    { view.webView.goBack() }
    func tabContentViewDidClickForward(_ view: TabContentView) { view.webView.goForward() }
    func tabContentViewDidClickReload(_ view: TabContentView)  { view.webView.reload() }
    func tabContentViewDidClickStop(_ view: TabContentView)    { view.webView.stopLoading() }
    func tabContentViewDidClickClose(_ view: TabContentView)   { window?.close() }

    func tabContentViewDidClickPin(_ view: TabContentView) {
        guard let tab = tabStore?.tabs[tabID] else { return }
        let newPinned = !tab.isPinned
        tabStore?.updatePinned(tabID: tabID, isPinned: newPinned)
        contentView.updatePinState(newPinned)
        applyPinLevel(newPinned)
    }

    // MARK: - WKUIDelegate (new windows)

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Open in a new tab/window of our own rather than letting WebKit do it.
        if let url = navigationAction.request.url {
            NotificationCenter.default.post(
                name: .tabRequestedNewWindow,
                object: nil,
                userInfo: ["url": url]
            )
        }
        return nil
    }

    // MARK: - Private

    private func persistFrame() {
        guard let frame = window?.frame else { return }
        tabStore?.updateFrame(tabID: tabID, frame: PersistedRect(from: frame))
    }

    private func applyPinLevel(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let tabWindowDidClose      = Notification.Name("tabWindowDidClose")
    static let tabRequestedNewWindow  = Notification.Name("tabRequestedNewWindow")
}
