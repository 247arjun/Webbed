import AppKit
import WebbedKit

// MARK: - LibraryWindowController

/// Master/detail Library window. Mirrors Noted's `AllNotesWindowController`.
@MainActor
final class LibraryWindowController: NSWindowController, NSToolbarDelegate {

    private var listVC:   TabsListViewController!
    private var detailVC: TabDetailViewController!
    private weak var tabStore: TabStore?

    private static let toolbarID    = NSToolbar.Identifier("LibraryToolbar")
    private static let searchID     = NSToolbarItem.Identifier("SearchItem")
    private static let createID     = NSToolbarItem.Identifier("CreateItem")
    private static let sortID       = NSToolbarItem.Identifier("SortItem")
    private static let folderID     = NSToolbarItem.Identifier("FolderItem")

    convenience init(
        tabStore: TabStore,
        onOpenTab: @escaping (UUID) -> Void,
        onCreateTab: @escaping () -> Void,
        isWindowOpen: @escaping (UUID) -> Bool
    ) {
        let listVC   = TabsListViewController(tabStore: tabStore)
        let detailVC = TabDetailViewController(tabStore: tabStore)

        listVC.onCreateTab    = onCreateTab
        listVC.isWindowOpen   = isWindowOpen
        listVC.onOpenTab      = onOpenTab

        // Single-click in list → preview in detail
        listVC.onSelectTab = { [weak detailVC] id in detailVC?.showTab(id: id) }

        // Delete from list context menu
        listVC.onDeleteTab = { [weak detailVC, weak tabStore] id in
            if detailVC?.currentTabID == id { detailVC?.clearDetail() }
            tabStore?.trash(tabID: id)
        }

        // Split view
        let splitVC = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: listVC)
        sidebar.minimumThickness = 240
        sidebar.maximumThickness = 400
        sidebar.canCollapse = false
        sidebar.holdingPriority = .defaultLow + 1

        let detail = NSSplitViewItem(viewController: detailVC)
        detail.minimumThickness = 360
        detail.canCollapse = false
        detail.titlebarSeparatorStyle = .none

        splitVC.addSplitViewItem(sidebar)
        splitVC.addSplitViewItem(detail)

        let window = NSWindow(contentViewController: splitVC)
        window.title = "Library"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 880, height: 560))
        window.minSize = NSSize(width: 640, height: 360)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("LibraryWindow")
        window.tabbingMode = .disallowed

        self.init(window: window)
        self.listVC = listVC
        self.detailVC = detailVC
        self.tabStore = tabStore

        // Detail-pane action wiring (after init: self is valid)
        listVC.onBucketChanged = { [weak self] bucket in
            guard let self else { return }
            self.detailVC.clearDetail()
            self.refreshFolderToolbarItem()
            self.window?.title = bucket == .active ? "Library"
                               : bucket == .archived ? "Archived"
                               : "Trash"
        }

        detailVC.onOpenTab    = { id in onOpenTab(id) }
        detailVC.onArchiveTab = { [weak tabStore] id in tabStore?.archive(tabID: id) }
        detailVC.onMoveToTrash = { [weak tabStore] id in tabStore?.trash(tabID: id) }
        detailVC.onRestoreTab = { [weak self, weak tabStore] id in
            guard let self else { return }
            switch self.listVC.currentBucket {
            case .archived: tabStore?.unarchive(tabID: id)
            case .trash:    tabStore?.restoreFromTrash(tabID: id)
            case .active:   break
            }
            self.setBucket(.active)
            self.listVC.selectTab(id: id)
            self.detailVC.showTab(id: id)
        }
        detailVC.onDeleteForever = { [weak tabStore] id in tabStore?.deleteForever(tabID: id) }
    }

    func showWindow() {
        if window?.toolbar == nil {
            let toolbar = NSToolbar(identifier: Self.toolbarID)
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window?.toolbar = toolbar
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setBucket(_ bucket: StorageBucket) {
        listVC.setBucket(bucket)
    }

    func selectTab(id: UUID) {
        listVC.selectTab(id: id)
        detailVC.showTab(id: id)
    }

    // MARK: - Toolbar

    private func refreshFolderToolbarItem() {
        guard let toolbar = window?.toolbar,
              let item = toolbar.items.first(where: { $0.itemIdentifier == Self.folderID }) as? NSMenuToolbarItem else { return }
        configureFolderItem(item)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {

        case Self.folderID:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Folder"
            item.toolTip = "Switch folder"
            item.showsIndicator = true
            configureFolderItem(item)
            return item

        case Self.searchID:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.searchField = listVC.searchField
            item.preferredWidthForSearchField = 200
            return item

        case Self.createID:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "New Tab"
            item.toolTip = "New Tab"
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")?
                .withSymbolConfiguration(cfg)
            item.target = listVC
            item.action = #selector(TabsListViewController.createClicked)
            return item

        case Self.sortID:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Sort"
            item.toolTip = "Sort tabs"
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            item.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "Sort")?
                .withSymbolConfiguration(cfg)
            item.showsIndicator = true
            let menu = NSMenu()
            for mode in TabSortMode.allCases {
                let mi = NSMenuItem(title: mode.displayName, action: #selector(sortModeSelected(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = mode.rawValue
                mi.image = NSImage(systemSymbolName: mode.iconName, accessibilityDescription: nil)
                if mode == listVC.sortMode { mi.state = .on }
                menu.addItem(mi)
            }
            item.menu = menu
            return item

        default: return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.folderID, Self.searchID, Self.createID, Self.sortID,
         .sidebarTrackingSeparator, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.folderID, Self.searchID, Self.createID, Self.sortID,
         .sidebarTrackingSeparator, .flexibleSpace, .space]
    }

    private func configureFolderItem(_ item: NSMenuToolbarItem) {
        let current = listVC.currentBucket
        let symbol: String
        switch current {
        case .active:   symbol = "tray.2"
        case .archived: symbol = "archivebox"
        case .trash:    symbol = "trash"
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Folder")?
            .withSymbolConfiguration(cfg)

        let menu = NSMenu()
        for bucket in StorageBucket.allCases {
            let title: String; let sym: String
            switch bucket {
            case .active:   title = "Tabs";     sym = "tray.2"
            case .archived: title = "Archived"; sym = "archivebox"
            case .trash:    title = "Trash";    sym = "trash"
            }
            let mi = NSMenuItem(title: title, action: #selector(folderItemSelected(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = bucket.rawValue
            mi.image = NSImage(systemSymbolName: sym, accessibilityDescription: nil)
            if bucket == current { mi.state = .on }
            menu.addItem(mi)
        }
        item.menu = menu
    }

    @objc private func folderItemSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let bucket = StorageBucket(rawValue: raw) else { return }
        setBucket(bucket)
    }

    @objc private func sortModeSelected(_ sender: NSMenuItem) {
        guard let mode = TabSortMode(rawValue: sender.tag) else { return }
        listVC.sortMode = mode
        if let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == Self.sortID }) as? NSMenuToolbarItem {
            for mi in item.menu.items { mi.state = mi.tag == mode.rawValue ? .on : .off }
        }
    }
}
