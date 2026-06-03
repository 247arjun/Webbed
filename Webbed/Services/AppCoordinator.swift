import AppKit
import WebKit
import WebbedKit

// MARK: - AppCoordinator

/// Central coordinator that owns the tab store, window manager, and
/// persistence service. Singleton accessed from `AppDelegate` and menu
/// commands. Mirrors Noted's `AppCoordinator`.
@MainActor
final class AppCoordinator: ObservableObject, TabIntentHost {

    static let shared = AppCoordinator()

    let tabStore: TabStore
    let windowManager: WindowManager
    private(set) var persistenceService: PersistenceService
    private var libraryWindowController: LibraryWindowController?
    private var iCloudObserver: iCloudChangeObserver?

    private init() {
        let dir = AppSettings.shared.effectiveSaveDirectory
        let persistence = FilePersistenceService(directory: dir)
        let store = TabStore(persistenceService: persistence)

        self.persistenceService = persistence
        self.tabStore = store
        self.windowManager = WindowManager(tabStore: store)

        if AppSettings.shared.syncWithICloud,
           StorageLocationResolver.iCloudDirectory() != nil {
            installICloudObserver(directory: dir)
        }

        store.purgeOldTrash()

        IntentHostRegistry.current = self
    }

    private func installICloudObserver(directory: URL) {
        let observer = iCloudChangeObserver()
        observer.start(tabsDirectory: directory)
        tabStore.attachICloudObserver(observer)
        iCloudObserver = observer
    }

    // MARK: - App lifecycle

    /// Called from applicationDidFinishLaunching.
    func start() {
        tabStore.loadAll()
        let behavior = AppSettings.shared.launchBehavior

        if tabStore.tabs.isEmpty {
            // First launch: open a single fresh tab.
            let tab = tabStore.createTab(url: AppSettings.shared.homepageURL)
            windowManager.openNewTabWindow(tabID: tab.id)
            showLibrary()
            return
        }

        switch behavior {
        case .libraryAndRestore:
            windowManager.restoreAllWindows()
            showLibrary()
        case .libraryOnly:
            showLibrary()
        case .restoreOnly:
            windowManager.restoreAllWindows()
        }

        if windowManager.openWindowCount == 0 && libraryWindowController?.window?.isVisible != true {
            // Fallback so the user always sees something.
            let tab = tabStore.createTab(url: AppSettings.shared.homepageURL)
            windowManager.openNewTabWindow(tabID: tab.id)
        }
    }

    func flushPendingSaves() {
        tabStore.flushPendingSaves()
    }

    // MARK: - Tab actions (menu commands)

    @objc func createNewTab() {
        let tab = tabStore.createTab(url: AppSettings.shared.homepageURL)
        windowManager.openNewTabWindow(tabID: tab.id)
    }

    @objc func duplicateCurrentTab() {
        guard let id = currentTabID(),
              let dup = tabStore.duplicateTab(tabID: id) else { return }
        windowManager.openNewTabWindow(tabID: dup.id)
    }

    @objc func closeCurrentTab() {
        NSApp.keyWindow?.performClose(nil)
    }

    @objc func reloadCurrentTab() {
        currentWebView()?.reload()
    }

    @objc func reloadFromOrigin() {
        currentWebView()?.reloadFromOrigin()
    }

    @objc func stopLoadingCurrentTab() {
        currentWebView()?.stopLoading()
    }

    @objc func goBackCurrentTab()    { currentWebView()?.goBack() }
    @objc func goForwardCurrentTab() { currentWebView()?.goForward() }

    @objc func zoomInCurrentTab() {
        if let wv = currentWebView() { wv.pageZoom = min(5.0, wv.pageZoom + 0.1) }
    }

    @objc func zoomOutCurrentTab() {
        if let wv = currentWebView() { wv.pageZoom = max(0.2, wv.pageZoom - 0.1) }
    }

    @objc func actualSizeCurrentTab() {
        if let wv = currentWebView() { wv.pageZoom = 1.0 }
    }

    // MARK: - Library window

    @objc func showLibrary() {
        ensureLibraryController().showWindow()
    }

    @objc func showArchive() {
        let ctrl = ensureLibraryController()
        ctrl.setBucket(.archived)
        ctrl.showWindow()
    }

    @objc func showTrash() {
        let ctrl = ensureLibraryController()
        ctrl.setBucket(.trash)
        ctrl.showWindow()
    }

    private func ensureLibraryController() -> LibraryWindowController {
        if let existing = libraryWindowController { return existing }
        let ctrl = LibraryWindowController(
            tabStore: tabStore,
            onOpenTab: { [weak self] id in self?.windowManager.openWindow(for: id) },
            onCreateTab: { [weak self] in self?.createNewTab() },
            isWindowOpen: { [weak self] id in self?.windowManager.isWindowOpen(for: id) ?? false }
        )
        libraryWindowController = ctrl
        return ctrl
    }

    // MARK: - Helpers

    private func currentController() -> TabWindowController? {
        NSApp.keyWindow?.windowController as? TabWindowController
    }

    private func currentTabID() -> UUID? { currentController()?.tabID }
    private func currentWebView() -> WKWebView? { currentController()?.contentView.webView }

    // MARK: - TabIntentHost

    func openTab(id: UUID) {
        windowManager.openWindow(for: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openNewTab(url: URL?) {
        let tab = tabStore.createTab(url: url ?? AppSettings.shared.homepageURL)
        windowManager.openNewTabWindow(tabID: tab.id)
        NSApp.activate(ignoringOtherApps: true)
    }
}
