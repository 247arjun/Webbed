import Foundation

#if canImport(AppKit)
import AppKit
#endif

// MARK: - InstalledBrowser

public struct InstalledBrowser: Identifiable, Hashable, Sendable {
    public let bundleID: String
    public let displayName: String
    public let url: URL

    public var id: String { bundleID }

    public init(bundleID: String, displayName: String, url: URL) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.url = url
    }
}

// MARK: - InstalledBrowsers

/// Enumerates installed apps that can handle `http://` / `https://`.
/// macOS only — on iOS the system default-browser setting is used directly,
/// so there's nothing to pick from inside the app.
public enum InstalledBrowsers {

    /// Pseudo bundle ID meaning "whatever the user's macOS default browser is".
    public static let systemDefaultBundleID = "__system_default__"

    #if os(macOS)
    /// All installed apps registered as http(s) handlers, minus Webbed itself,
    /// sorted by display name. Always begins with a "System Default" entry.
    @MainActor
    public static func all() -> [InstalledBrowser] {
        let workspace = NSWorkspace.shared
        let probe = URL(string: "https://apple.com")!

        let urls = workspace.urlsForApplications(toOpen: probe)
        let webbedBundle = Bundle.main.bundleIdentifier

        var seen: Set<String> = []
        var browsers: [InstalledBrowser] = []
        for url in urls {
            guard let bundle = Bundle(url: url),
                  let bid = bundle.bundleIdentifier else { continue }
            if bid == webbedBundle { continue }
            if seen.contains(bid) { continue }
            seen.insert(bid)
            let name = (FileManager.default.displayName(atPath: url.path) as NSString)
                .deletingPathExtension
            browsers.append(InstalledBrowser(bundleID: bid, displayName: name, url: url))
        }
        browsers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let systemDefault = InstalledBrowser(
            bundleID: systemDefaultBundleID,
            displayName: "System Default",
            url: workspace.urlForApplication(toOpen: probe) ?? probe
        )
        return [systemDefault] + browsers
    }

    /// Open `url` in the chosen browser. Falls back to the system default if
    /// the bundle ID can't be resolved.
    @MainActor
    public static func open(_ url: URL, with bundleID: String) {
        let workspace = NSWorkspace.shared
        if bundleID == systemDefaultBundleID {
            workspace.open(url)
            return
        }
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            workspace.open([url], withApplicationAt: appURL, configuration: config) { _, error in
                if let error {
                    Log.web.error("Failed to open \(url, privacy: .public) in \(bundleID, privacy: .public): \(error.localizedDescription)")
                    Task { @MainActor in NSWorkspace.shared.open(url) }
                }
            }
            return
        }
        // Fallback.
        workspace.open(url)
    }
    #endif
}
