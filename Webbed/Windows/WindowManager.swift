import AppKit
import WebbedKit

// MARK: - WindowManager

/// Creates, tracks, and manages tear-out tab windows. Mirrors Noted's
/// `WindowManager` 1:1.
@MainActor
final class WindowManager {

    private var controllers: [UUID: TabWindowController] = [:]
    private weak var tabStore: TabStore?
    private var cascadePoint: NSPoint = .zero

    init(tabStore: TabStore) {
        self.tabStore = tabStore

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowClose(_:)),
            name: .tabWindowDidClose,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewWindowRequest(_:)),
            name: .tabRequestedNewWindow,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    var openWindowCount: Int { controllers.count }

    func isWindowOpen(for tabID: UUID) -> Bool { controllers[tabID] != nil }

    /// Open (or bring to front) the window for an existing tab.
    func openWindow(for tabID: UUID) {
        guard let store = tabStore, let tab = store.tabs[tabID] else {
            Log.window.error("Cannot open window: tab \(tabID, privacy: .public) not in store")
            return
        }
        if let existing = controllers[tabID] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let theme = ThemeRegistry.theme(for: tab.themeID)
        let frame = validatedFrame(tab.frame)
        let ctrl = TabWindowController(
            tabID: tabID, tabStore: store,
            frame: frame.cgRect, theme: theme
        )
        ctrl.loadContent(from: tab)
        controllers[tabID] = ctrl
        ctrl.window?.makeKeyAndOrderFront(nil)
        store.markClosed(tabID: tabID, isClosed: false)
    }

    /// Open a brand-new tab with a cascaded position.
    func openNewTabWindow(tabID: UUID) {
        guard let store = tabStore, var tab = store.tabs[tabID] else { return }
        let frame = nextCascadedFrame()
        tab.frame = PersistedRect(from: frame)
        store.updateFrame(tabID: tabID, frame: tab.frame)

        let theme = ThemeRegistry.theme(for: tab.themeID)
        let ctrl = TabWindowController(
            tabID: tabID, tabStore: store,
            frame: frame, theme: theme
        )
        ctrl.loadContent(from: tab)
        controllers[tabID] = ctrl

        if let window = ctrl.window {
            cascadePoint = window.cascadeTopLeft(from: cascadePoint)
            window.makeKeyAndOrderFront(nil)
        }
        store.markClosed(tabID: tabID, isClosed: false)
    }

    /// Close a window without trashing the tab.
    func closeWindow(for tabID: UUID) {
        controllers[tabID]?.window?.close()
    }

    /// Restore tab windows after launch. Honours `LaunchBehavior`.
    /// Pinned tabs and previously-open tabs both come back.
    func restoreAllWindows() {
        guard let store = tabStore else { return }
        let toRestore = store.tabs.values
            .filter { !$0.isClosed || $0.isPinnedTab }
            .sorted(by: { $0.createdAt < $1.createdAt })
        for tab in toRestore { openWindow(for: tab.id) }
        Log.restore.info("Restored \(toRestore.count) tab windows")
    }

    func closeAllWindows() {
        for (_, c) in controllers { c.window?.close() }
    }

    // MARK: - Private

    @objc private func handleWindowClose(_ note: Notification) {
        guard let tabID = note.object as? UUID else { return }
        controllers.removeValue(forKey: tabID)
    }

    @objc private func handleNewWindowRequest(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? URL, let store = tabStore else { return }
        let tab = store.createTab(url: url)
        openNewTabWindow(tabID: tab.id)
    }

    private func nextCascadedFrame() -> NSRect {
        guard let screen = NSScreen.main else { return PersistedRect.default.cgRect }
        let screenFrame = screen.visibleFrame
        if cascadePoint == .zero {
            cascadePoint = NSPoint(x: screenFrame.minX + 100, y: screenFrame.maxY - 60)
        }
        let width:  CGFloat = 1024
        let height: CGFloat = 720
        let origin = NSPoint(x: cascadePoint.x, y: cascadePoint.y - height)
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }

    private func validatedFrame(_ frame: PersistedRect) -> PersistedRect {
        let rect = frame.cgRect
        let screens = NSScreen.screens
        let onScreen = screens.contains { $0.visibleFrame.intersects(rect) }
        if onScreen { return frame }
        guard let main = NSScreen.main else { return frame }
        let v = main.visibleFrame
        var clamped = rect
        clamped.size.width  = min(clamped.width,  v.width)
        clamped.size.height = min(clamped.height, v.height)
        clamped.origin.x = max(v.minX, min(clamped.origin.x, v.maxX - clamped.width))
        clamped.origin.y = max(v.minY, min(clamped.origin.y, v.maxY - clamped.height))
        return PersistedRect(from: clamped)
    }
}
