import AppKit
import WebbedKit

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = buildMainMenu()
        AppCoordinator.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppCoordinator.shared.flushPendingSaves()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppCoordinator.shared.createNewTab() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newTab = menu.addItem(
            withTitle: "New Tab",
            action: #selector(AppCoordinator.createNewTab),
            keyEquivalent: ""
        )
        newTab.target = AppCoordinator.shared
        newTab.image = NSImage(systemSymbolName: "plus.square",
                               accessibilityDescription: "New Tab")
        return menu
    }

    // MARK: - Main Menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Webbed",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…",
                                       action: #selector(showSettings),
                                       keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Webbed",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Webbed",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        let newTab = fileMenu.addItem(
            withTitle: "New Tab",
            action: #selector(AppCoordinator.createNewTab),
            keyEquivalent: "t"
        )
        newTab.target = AppCoordinator.shared

        let dup = fileMenu.addItem(
            withTitle: "Duplicate Tab",
            action: #selector(AppCoordinator.duplicateCurrentTab),
            keyEquivalent: ""
        )
        dup.target = AppCoordinator.shared

        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Close Tab",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        fileMenu.addItem(.separator())
        let library = fileMenu.addItem(
            withTitle: "Library…",
            action: #selector(AppCoordinator.showLibrary),
            keyEquivalent: "L"
        )
        library.keyEquivalentModifierMask = [.command, .shift]
        library.target = AppCoordinator.shared
        let archived = fileMenu.addItem(
            withTitle: "Archived Tabs…",
            action: #selector(AppCoordinator.showArchive),
            keyEquivalent: ""
        )
        archived.target = AppCoordinator.shared
        let trash = fileMenu.addItem(
            withTitle: "Trash…",
            action: #selector(AppCoordinator.showTrash),
            keyEquivalent: ""
        )
        trash.target = AppCoordinator.shared

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu (standard)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo",       action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",        action: #selector(NSText.cut(_:)),   keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",       action: #selector(NSText.copy(_:)),  keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",      action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        let reload = viewMenu.addItem(
            withTitle: "Reload Tab",
            action: #selector(AppCoordinator.reloadCurrentTab),
            keyEquivalent: "r"
        )
        reload.target = AppCoordinator.shared
        let forceReload = viewMenu.addItem(
            withTitle: "Reload From Origin",
            action: #selector(AppCoordinator.reloadFromOrigin),
            keyEquivalent: "r"
        )
        forceReload.keyEquivalentModifierMask = [.command, .shift]
        forceReload.target = AppCoordinator.shared
        let stop = viewMenu.addItem(
            withTitle: "Stop Loading",
            action: #selector(AppCoordinator.stopLoadingCurrentTab),
            keyEquivalent: "."
        )
        stop.target = AppCoordinator.shared
        viewMenu.addItem(.separator())
        let zoomIn  = viewMenu.addItem(
            withTitle: "Zoom In",
            action: #selector(AppCoordinator.zoomInCurrentTab),
            keyEquivalent: "+"
        )
        zoomIn.target = AppCoordinator.shared
        let zoomOut = viewMenu.addItem(
            withTitle: "Zoom Out",
            action: #selector(AppCoordinator.zoomOutCurrentTab),
            keyEquivalent: "-"
        )
        zoomOut.target = AppCoordinator.shared
        let actual = viewMenu.addItem(
            withTitle: "Actual Size",
            action: #selector(AppCoordinator.actualSizeCurrentTab),
            keyEquivalent: "0"
        )
        actual.target = AppCoordinator.shared
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // History menu
        let historyMenu = NSMenu(title: "History")
        let back = historyMenu.addItem(
            withTitle: "Back",
            action: #selector(AppCoordinator.goBackCurrentTab),
            keyEquivalent: "["
        )
        back.target = AppCoordinator.shared
        let fwd  = historyMenu.addItem(
            withTitle: "Forward",
            action: #selector(AppCoordinator.goForwardCurrentTab),
            keyEquivalent: "]"
        )
        fwd.target = AppCoordinator.shared
        let historyMenuItem = NSMenuItem()
        historyMenuItem.submenu = historyMenu
        mainMenu.addItem(historyMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    // MARK: - Settings

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
