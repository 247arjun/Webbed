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
    private var themePopover: NSPopover?
    private var liveModePopover: NSPopover?
    private var permissionsPopover: NSPopover?
    private var liveRefreshTimer: Timer?

    // MARK: - Init

    init(tabID: UUID, tabStore: TabStore,
         permissionStore: PermissionStore?,
         frame: NSRect, theme: WebbedTheme) {
        self.tabID = tabID
        self.tabStore = tabStore
        self.permissionStore = permissionStore

        // Per-origin autoplay / popup grants from the initial URL (if any).
        let initialHost = tabStore.tabs[tabID]?.url?.host
        let autoplay = permissionStore?.decision(for: initialHost, kind: .autoplay) == .allow
        let popups   = permissionStore?.decision(for: initialHost, kind: .popups)   == .allow

        let webView = WebViewFactory.make(autoplayAllowed: autoplay, popupsAllowed: popups)
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

        installFaviconScript(on: webView)
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
        if let url = tab.url {
            contentView.webView.load(URLRequest(url: url))
        } else if let home = AppSettings.shared.homepageURL {
            contentView.webView.load(URLRequest(url: home))
        }
    }

    func applyTheme(_ theme: WebbedTheme) {
        contentView.applyTheme(theme)
        // Reapply live-mode tint (the theme pass resets contentTintColor).
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

    func tabContentViewDidClickTheme(_ view: TabContentView, sourceButton: NSButton) {
        let currentID = tabStore?.tabs[tabID]?.themeID ?? ThemeRegistry.defaultThemeID
        let picker = ThemePickerViewController(currentThemeID: currentID) { [weak self] themeID in
            guard let self else { return }
            self.tabStore?.updateTheme(tabID: self.tabID, themeID: themeID)
            self.applyTheme(ThemeRegistry.theme(for: themeID))
            self.themePopover?.close()
        }
        let popover = NSPopover()
        popover.contentViewController = picker
        popover.behavior = .transient
        popover.show(relativeTo: sourceButton.bounds, of: sourceButton, preferredEdge: .minY)
        themePopover = popover
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
        // Per-origin popup gate.
        let host = navigationAction.sourceFrame.request.url?.host ?? currentHost()
        if permissionStore?.decision(for: host, kind: .popups) == .deny {
            Log.web.debug("Pop-up suppressed for \(host ?? "", privacy: .public)")
            return nil
        }
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
            Task { @MainActor in self?.captureSnapshot() }
        }
        snapshotWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
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

    // MARK: - Favicon capture (script-message handler)

    private func installFaviconScript(on webView: WKWebView) {
        let source = #"""
        (function() {
            function bestIcon() {
                var links = document.querySelectorAll('link[rel~="icon"]');
                if (links.length === 0) return null;
                // Pick the largest sized icon if `sizes` is declared.
                var best = null, bestSize = 0;
                for (var i = 0; i < links.length; i++) {
                    var l = links[i];
                    var sizesAttr = (l.getAttribute('sizes') || '').toLowerCase();
                    var sz = 0;
                    if (sizesAttr === 'any') { sz = 9999; }
                    else {
                        var match = sizesAttr.match(/(\d+)x\d+/);
                        if (match) sz = parseInt(match[1], 10);
                    }
                    if (best === null || sz > bestSize) { best = l; bestSize = sz; }
                }
                return best ? best.href : null;
            }
            function report() {
                var href = bestIcon();
                if (href) {
                    window.webkit.messageHandlers.favicon.postMessage(href);
                }
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
        // WKScriptMessage props are MainActor-isolated; hop before reading.
        Task { @MainActor in
            guard message.name == "favicon",
                  let href = message.body as? String,
                  let url = URL(string: href) else { return }
            // Download + cache the actual bytes, then record the cache ref
            // on the TabRecord so list rows can render the favicon.
            if let ref = await FaviconCache.shared.fetch(iconURL: url) {
                self.tabStore?.updateFaviconRef(tabID: self.tabID, ref: ref)
            }
        }
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
