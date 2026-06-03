import AppKit
import WebKit
import WebbedKit
import CryptoKit

// MARK: - TabWindowController

/// Manages one tab window. Coordinates the content view, WKWebView KVO, and
/// the TabStore.
@MainActor
final class TabWindowController: NSWindowController,
                                 NSWindowDelegate,
                                 TabContentViewDelegate,
                                 WKNavigationDelegate,
                                 WKUIDelegate,
                                 WKScriptMessageHandler {

    let tabID: UUID
    private weak var tabStore: TabStore?
    private weak var permissionStore: PermissionStore?
    private(set) var contentView: TabContentView
    private var kvoObservers: [NSKeyValueObservation] = []
    private var snapshotWorkItem: DispatchWorkItem?
    private var liveModePopover: NSPopover?
    private var permissionsPopover: NSPopover?
    private var liveRefreshTimer: Timer?

    // MARK: - Init

    init(tabID: UUID, tabStore: TabStore,
         permissionStore: PermissionStore?,
         frame: NSRect) {
        self.tabID = tabID
        self.tabStore = tabStore
        self.permissionStore = permissionStore

        // Per-origin autoplay / popup grants from the initial URL (if any).
        let initialHost = tabStore.tabs[tabID]?.url?.host
        let autoplay = permissionStore?.decision(for: initialHost, kind: .autoplay) == .allow
        let popups   = permissionStore?.decision(for: initialHost, kind: .popups)   == .allow

        let webView = WebViewFactory.make(autoplayAllowed: autoplay, popupsAllowed: popups)

        // Initial chrome: derive from persisted dominantColor (if any) or
        // fall through to system chrome.
        let initialTheme: WebbedTheme = {
            guard AppSettings.shared.chromeStyle == .color,
                  let tab = tabStore.tabs[tabID], tab.autoTintFromSite,
                  let data = tab.dominantColor,
                  let color = DominantColor.color(from: data) else { return .system() }
            return .color(from: color)
        }()
        contentView = TabContentView(tabID: tabID, theme: initialTheme, webView: webView)

        let window = TabWindow(contentRect: frame)
        window.contentView = contentView
        contentView.frame = window.contentView!.bounds
        contentView.autoresizingMask = [.width, .height]

        super.init(window: window)

        window.delegate = self
        contentView.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self

        installPageScripts(on: webView)
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
        contentView.updateLiveModeGlyph(tab.liveModeInterval)
        applyPinLevel(tab.isPinned)
        scheduleLiveRefresh(interval: tab.liveModeInterval)
        // Apply persisted dominant color (if any) immediately so the window
        // opens with the right tint even before the page loads.
        applyCurrentTheme()
        if let url = tab.url {
            contentView.webView.load(URLRequest(url: url))
        } else if let home = AppSettings.shared.homepageURL {
            contentView.webView.load(URLRequest(url: home))
        }
    }

    func applyTheme(_ theme: WebbedTheme) {
        contentView.applyTheme(theme)
        if let tab = tabStore?.tabs[tabID] {
            contentView.updateLiveModeGlyph(tab.liveModeInterval)
        }
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
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = nil
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

    func tabContentViewDidClickLiveMode(_ view: TabContentView, sourceButton: NSButton) {
        let current = tabStore?.tabs[tabID]?.liveModeInterval ?? .off
        let picker = LiveModePopoverController(current: current) { [weak self] interval in
            guard let self else { return }
            self.tabStore?.updateLiveMode(tabID: self.tabID, interval: interval)
            self.contentView.updateLiveModeGlyph(interval)
            self.scheduleLiveRefresh(interval: interval)
            self.liveModePopover?.close()
        }
        let popover = NSPopover()
        popover.contentViewController = picker
        popover.behavior = .transient
        popover.show(relativeTo: sourceButton.bounds, of: sourceButton, preferredEdge: .minY)
        liveModePopover = popover
    }

    func tabContentViewDidClickOpenExternal(_ view: TabContentView) {
        guard let url = view.webView.url ?? tabStore?.tabs[tabID]?.url else { return }
        InstalledBrowsers.open(url, with: AppSettings.shared.externalBrowserBundleID)
    }

    func tabContentViewDidClickTrash(_ view: TabContentView) {
        menuTrash()
    }

    func tabContentViewDidClickMore(_ view: TabContentView, sourceButton: NSButton) {
        let menu = NSMenu()
        let reload = menu.addItem(withTitle: "Reload", action: #selector(menuReload), keyEquivalent: "")
        reload.target = self
        let dup = menu.addItem(withTitle: "Duplicate Tab", action: #selector(menuDuplicate), keyEquivalent: "")
        dup.target = self
        menu.addItem(.separator())

        // Per-origin quick toggles.
        if let host = currentHost() {
            let jsRule = permissionStore?.decision(for: host, kind: .javascript) ?? .allow
            let jsItem = menu.addItem(
                withTitle: jsRule == .deny ? "Enable JavaScript on \(host)" : "Disable JavaScript on \(host)",
                action: #selector(menuToggleJavaScript),
                keyEquivalent: ""
            )
            jsItem.target = self
            if jsRule == .deny { jsItem.state = .on }

            let popupRule = permissionStore?.decision(for: host, kind: .popups) ?? .deny
            let popItem = menu.addItem(
                withTitle: popupRule == .allow ? "Block Pop-ups on \(host)" : "Allow Pop-ups on \(host)",
                action: #selector(menuTogglePopups),
                keyEquivalent: ""
            )
            popItem.target = self

            let siteSettings = menu.addItem(
                withTitle: "Site Settings…",
                action: #selector(menuOpenSiteSettings(_:)),
                keyEquivalent: ""
            )
            siteSettings.target = self
            siteSettings.representedObject = sourceButton
            menu.addItem(.separator())
        }

        let pinTab = menu.addItem(
            withTitle: (tabStore?.tabs[tabID]?.isPinnedTab ?? false) ? "Unpin from Library" : "Pin in Library",
            action: #selector(menuTogglePinnedTab),
            keyEquivalent: ""
        )
        pinTab.target = self
        let autoTint = menu.addItem(
            withTitle: "Match Site Color",
            action: #selector(menuToggleAutoTint),
            keyEquivalent: ""
        )
        autoTint.target = self
        autoTint.state = (tabStore?.tabs[tabID]?.autoTintFromSite ?? true) ? .on : .off
        autoTint.isEnabled = AppSettings.shared.chromeStyle == .color
        menu.addItem(.separator())
        let archive = menu.addItem(withTitle: "Archive Tab", action: #selector(menuArchive), keyEquivalent: "")
        archive.target = self
        let trash = menu.addItem(withTitle: "Move to Trash", action: #selector(menuTrash), keyEquivalent: "")
        trash.target = self
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sourceButton.bounds.maxY + 4),
                   in: sourceButton)
    }

    @objc private func menuReload()           { contentView.webView.reload() }
    @objc private func menuDuplicate() {
        guard let dup = tabStore?.duplicateTab(tabID: tabID) else { return }
        NotificationCenter.default.post(name: .tabDuplicated, object: dup.id)
    }
    @objc private func menuTogglePinnedTab() {
        guard let tab = tabStore?.tabs[tabID] else { return }
        tabStore?.updatePinnedTab(tabID: tabID, isPinnedTab: !tab.isPinnedTab)
    }
    @objc private func menuToggleAutoTint() {
        guard let tab = tabStore?.tabs[tabID] else { return }
        tabStore?.updateAutoTintFromSite(tabID: tabID, enabled: !tab.autoTintFromSite)
        // Re-pick the theme. If turning back on and we already have a
        // dominantColor cached, it kicks in immediately.
        if tab.autoTintFromSite == false {
            // We just enabled auto-tint.
            applyCurrentTheme()
        } else {
            // We just disabled it — fall back to system chrome.
            applyCurrentTheme()
        }
    }
    @objc private func menuArchive() {
        tabStore?.archive(tabID: tabID)
        window?.close()
    }
    @objc private func menuTrash() {
        tabStore?.trash(tabID: tabID)
        window?.close()
    }

    @objc private func menuToggleJavaScript() {
        guard let host = currentHost(), let store = permissionStore else { return }
        let current = store.decision(for: host, kind: .javascript)
        let next: PermissionDecision = current == .deny ? .allow : .deny
        store.setDecision(for: host, kind: .javascript, decision: next)
        contentView.webView.reload()
    }

    @objc private func menuTogglePopups() {
        guard let host = currentHost(), let store = permissionStore else { return }
        let current = store.decision(for: host, kind: .popups)
        let next: PermissionDecision = current == .allow ? .deny : .allow
        store.setDecision(for: host, kind: .popups, decision: next)
    }

    @objc private func menuOpenSiteSettings(_ sender: NSMenuItem) {
        guard let host = currentHost(),
              let store = permissionStore,
              let anchor = sender.representedObject as? NSView else { return }
        let vc = SitePermissionsPopoverController(host: host, store: store) { [weak self] in
            // Reload after the popover closes if any reload-required rules
            // were changed (cheapest correct behavior).
            self?.contentView.webView.reload()
        }
        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        permissionsPopover = popover
    }

    // MARK: - WKUIDelegate (new windows)

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // The per-origin popup permission is enforced upstream at WebView
        // construction time via `preferences.javaScriptCanOpenWindowsAutomatically`
        // (see WebViewFactory). When that flag is false, WebKit blocks
        // unattended `window.open()` calls before they ever reach this
        // delegate. By the time we get here the action is always either
        // (a) a JS popup with a user gesture, or (b) an explicit user
        // command like "Open Link in New Window" / ⌘-shift-click. All of
        // those should always open — gating again here would (and did)
        // silently swallow the user's own clicks.
        if let url = navigationAction.request.url {
            NotificationCenter.default.post(
                name: .tabRequestedNewWindow,
                object: nil,
                userInfo: ["url": url]
            )
        }
        return nil
    }

    // MARK: - WKUIDelegate (capture & geolocation prompts)

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
        var anyDeny = false; var allAllow = true
        for kind in kinds {
            let d = permissionStore?.decision(for: host, kind: kind) ?? kind.defaultDecision
            if d == .deny  { anyDeny = true }
            if d != .allow { allAllow = false }
        }
        if anyDeny  { return .deny }
        if allAllow { return .grant }
        return .prompt
    }

    // MARK: - WKNavigationDelegate (snapshot trigger)

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {

        let url  = navigationAction.request.url
        let host = url?.host

        // 1. Per-origin "always open in external browser" → hand off + cancel.
        if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame?.isMainFrame == true,
           let host, let url,
           permissionStore?.decision(for: host, kind: .openInExternal) == .allow,
           url.host == host {
            InstalledBrowsers.open(url, with: AppSettings.shared.externalBrowserBundleID)
            return (.cancel, preferences)
        }

        // 2. Mixed-content gate: block http subresources inside https main
        //    documents unless the origin opts in.
        if let url, url.scheme == "http",
           let main = webView.url, main.scheme == "https",
           navigationAction.targetFrame?.isMainFrame != true,
           permissionStore?.decision(for: main.host, kind: .insecureContent) != .allow {
            Log.web.debug("Blocked insecure subresource \(url.absoluteString, privacy: .public)")
            return (.cancel, preferences)
        }

        // 3. Per-origin JavaScript gate.
        let jsAllowed = permissionStore?.decision(for: host, kind: .javascript) != .deny
        preferences.allowsContentJavaScript = jsAllowed

        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Debounce snapshot capture so rapid navigations don't churn.
        snapshotWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.captureSnapshot()
                self?.fetchDefaultFaviconIfNeeded()
            }
        }
        snapshotWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // Fresh navigation — forget any prior page's theme-color so a
        // late favicon callback can supply a color for the new origin.
        resetThemingForNavigation()
    }

    private func captureSnapshot() {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        contentView.webView.takeSnapshot(with: config) { [weak self] image, error in
            guard let self, let image else {
                if let error { Log.web.debug("Snapshot failed: \(error.localizedDescription)") }
                return
            }
            Task { @MainActor in
                guard let png = Self.pngData(from: image, maxBytes: 80 * 1024) else { return }
                let ref = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                do {
                    try self.tabStore?.persistenceService.saveSnapshot(tabID: self.tabID, pngData: png)
                    self.tabStore?.updateSnapshotRef(tabID: self.tabID, ref: ref)
                } catch {
                    Log.persist.error("Snapshot save failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Downscale + PNG-encode an NSImage, retrying smaller sizes until under
    /// `maxBytes`. Returns nil if we can't get under the cap.
    private static func pngData(from image: NSImage, maxBytes: Int) -> Data? {
        let targetWidths: [CGFloat] = [800, 600, 480, 360, 280]
        for w in targetWidths {
            guard let resized = resize(image, toWidth: w),
                  let tiff = resized.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            if png.count <= maxBytes { return png }
        }
        return nil
    }

    private static func resize(_ image: NSImage, toWidth width: CGFloat) -> NSImage? {
        let aspect = image.size.height / max(image.size.width, 1)
        let size = NSSize(width: width, height: width * aspect)
        let new = NSImage(size: size)
        new.lockFocus()
        defer { new.unlockFocus() }
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        return new
    }

    // MARK: - Page scripts (favicon + theme-color)

    private func installPageScripts(on webView: WKWebView) {
        let ucc = webView.configuration.userContentController
        ucc.addUserScript(WebViewFactory.faviconUserScript)
        ucc.addUserScript(WebViewFactory.themeColorUserScript)
        ucc.add(self, name: "favicon")
        ucc.add(self, name: "themeColor")
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        Task { @MainActor in
            switch message.name {
            case "favicon":
                guard let href = message.body as? String,
                      let url = URL(string: href) else { return }
                self.faviconReportedForCurrentPage = true
                if let ref = await FaviconCache.shared.fetch(iconURL: url) {
                    self.tabStore?.updateFaviconRef(tabID: self.tabID, ref: ref)
                    self.deriveDominantColorFromFaviconIfNeeded(ref: ref)
                }

            case "themeColor":
                let raw = (message.body as? String) ?? ""
                self.applyPageThemeColor(raw)

            default:
                break
            }
        }
    }

    // MARK: - Theming pipeline

    /// True once the page has explicitly reported a `theme-color`. Prevents
    /// the favicon-derived color from overriding it.
    private var pageThemeColorReported = false
    /// True once a favicon URL has been reported (via `<link rel=icon>` or
    /// the `/favicon.ico` fallback) for the current navigation.
    private var faviconReportedForCurrentPage = false

    /// Reset between navigations so a new origin gets a fresh sampling pass.
    private func resetThemingForNavigation() {
        pageThemeColorReported = false
        faviconReportedForCurrentPage = false
        // Clear the persisted dominant color so chrome falls back to System
        // (or the new page's color, whichever arrives first). Otherwise the
        // old origin's tint sticks until B reports something — and if B
        // never does, it sticks forever.
        tabStore?.updateDominantColor(tabID: tabID, rgba: nil)
        applyCurrentTheme()
    }

    private func applyPageThemeColor(_ raw: String) {
        guard AppSettings.shared.chromeStyle == .color,
              tabStore?.tabs[tabID]?.autoTintFromSite ?? true else { return }

        if let color = DominantColor.parseCSS(raw), !raw.isEmpty {
            pageThemeColorReported = true
            updateDominantColor(color)
        } else if raw.isEmpty {
            // Page cleared the meta — fall back to favicon sample if we have one.
            pageThemeColorReported = false
            if let ref = tabStore?.tabs[tabID]?.faviconRef {
                deriveDominantColorFromFaviconIfNeeded(ref: ref)
            }
        }
    }

    private func deriveDominantColorFromFaviconIfNeeded(ref: String) {
        guard AppSettings.shared.chromeStyle == .color,
              tabStore?.tabs[tabID]?.autoTintFromSite ?? true,
              !pageThemeColorReported else { return }
        faviconReportedForCurrentPage = true
        guard let image = FaviconCache.shared.image(forRef: ref),
              let color = DominantColor.sample(from: image) else { return }
        updateDominantColor(color)
    }

    /// If neither the page nor the favicon script has reported anything by
    /// the time the page finishes loading, fall back to `<origin>/favicon.ico`
    /// — the legacy convention that sites like Hacker News still rely on.
    private func fetchDefaultFaviconIfNeeded() {
        guard !faviconReportedForCurrentPage,
              !pageThemeColorReported,
              let url = contentView.webView.url,
              let scheme = url.scheme, scheme.hasPrefix("http"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        guard let iconURL = components.url else { return }
        faviconReportedForCurrentPage = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let ref = await FaviconCache.shared.fetch(iconURL: iconURL) {
                self.tabStore?.updateFaviconRef(tabID: self.tabID, ref: ref)
                self.deriveDominantColorFromFaviconIfNeeded(ref: ref)
            }
        }
    }

    private func updateDominantColor(_ color: PlatformColor) {
        let data = DominantColor.data(from: color)
        tabStore?.updateDominantColor(tabID: tabID, rgba: data)
        applyCurrentTheme()
    }

    /// Apply the WebbedTheme implied by the current AppSettings + TabRecord
    /// state. Call after anything that could change the resolved theme.
    func applyCurrentTheme() {
        let theme = resolvedTheme()
        contentView.applyTheme(theme)
        if let tab = tabStore?.tabs[tabID] {
            contentView.updateLiveModeGlyph(tab.liveModeInterval)
        }
    }

    private func resolvedTheme() -> WebbedTheme {
        let chromeStyle = AppSettings.shared.chromeStyle
        guard chromeStyle == .color else { return .system() }
        guard let tab = tabStore?.tabs[tabID], tab.autoTintFromSite,
              let data = tab.dominantColor,
              let color = DominantColor.color(from: data) else { return .system() }
        return .color(from: color)
    }

    // MARK: - Private

    private func persistFrame() {
        guard let frame = window?.frame else { return }
        tabStore?.updateFrame(tabID: tabID, frame: PersistedRect(from: frame))
    }

    private func applyPinLevel(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
    }

    // MARK: - Live Mode

    private func scheduleLiveRefresh(interval: LiveModeInterval) {
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = nil
        guard let seconds = interval.seconds else {
            Log.web.debug("Live Mode disabled for \(self.tabID, privacy: .public)")
            return
        }
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.contentView.webView.reload()
            }
        }
        // Keep firing during scroll / modal panels.
        RunLoop.main.add(timer, forMode: .common)
        liveRefreshTimer = timer
        Log.web.info("Live Mode \(interval.shortLabel, privacy: .public) for \(self.tabID, privacy: .public)")
    }

    // MARK: - Origin helper

    private func currentHost() -> String? {
        contentView.webView.url?.host ?? tabStore?.tabs[tabID]?.url?.host
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let tabWindowDidClose      = Notification.Name("tabWindowDidClose")
    static let tabRequestedNewWindow  = Notification.Name("tabRequestedNewWindow")
    static let tabDuplicated          = Notification.Name("tabDuplicated")
}
