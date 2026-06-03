import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - LaunchBehavior

public enum LaunchBehavior: Int, CaseIterable, Sendable {
    case libraryAndRestore = 0
    case libraryOnly       = 1
    case restoreOnly       = 2

    public var displayName: String {
        switch self {
        case .libraryAndRestore: return "Library + Restore Pinned Tabs"
        case .libraryOnly:       return "Library Only"
        case .restoreOnly:       return "Restore Pinned Tabs Only"
        }
    }
}

// MARK: - AppSettings

/// Centralised app settings backed by `UserDefaults`. Cross-platform.
@MainActor
public final class AppSettings {

    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let saveLocationBookmark = "saveLocationBookmark"
        static let saveLocationPath     = "saveLocationPath"
        static let defaultThemeID       = "defaultThemeID"
        static let launchBehavior       = "launchBehavior"
        static let searchProvider       = "searchProvider"
        static let homepageURL          = "homepageURL"
        static let mobileBreakpoint     = "mobileBreakpoint"
        static let syncWithICloud       = "syncWithICloud"
        static let syncTabPreviews      = "syncTabPreviews"
    }

    private init() {}

    // MARK: - Sync

    public var syncWithICloud: Bool {
        get {
            if defaults.object(forKey: Key.syncWithICloud) != nil {
                return defaults.bool(forKey: Key.syncWithICloud)
            }
            return StorageLocationResolver.iCloudAvailable
        }
        set { defaults.set(newValue, forKey: Key.syncWithICloud) }
    }

    public var syncTabPreviews: Bool {
        get {
            if defaults.object(forKey: Key.syncTabPreviews) != nil {
                return defaults.bool(forKey: Key.syncTabPreviews)
            }
            return true
        }
        set { defaults.set(newValue, forKey: Key.syncTabPreviews) }
    }

    // MARK: - Save location (macOS only beyond display)

    #if os(macOS)
    public var customSaveLocationURL: URL? {
        get {
            guard let bookmark = defaults.data(forKey: Key.saveLocationBookmark) else { return nil }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            if isStale,
               let fresh = try? url.bookmarkData(options: [.withSecurityScope]) {
                defaults.set(fresh, forKey: Key.saveLocationBookmark)
            }
            return url
        }
        set {
            if let url = newValue {
                let bookmark = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                defaults.set(bookmark, forKey: Key.saveLocationBookmark)
                defaults.set(url.path, forKey: Key.saveLocationPath)
            } else {
                defaults.removeObject(forKey: Key.saveLocationBookmark)
                defaults.removeObject(forKey: Key.saveLocationPath)
            }
        }
    }
    #else
    public var customSaveLocationURL: URL? { nil }
    #endif

    public var saveLocationDisplayPath: String {
        if syncWithICloud { return "iCloud Drive › Webbed" }
        #if os(macOS)
        if let path = defaults.string(forKey: Key.saveLocationPath) {
            return (path as NSString).abbreviatingWithTildeInPath
        }
        #endif
        return defaultSaveDirectory.path
    }

    /// The actual directory to use right now.
    public var effectiveSaveDirectory: URL {
        if syncWithICloud, let iCloud = StorageLocationResolver.iCloudDirectory() {
            return iCloud
        }
        #if os(macOS)
        if let custom = customSaveLocationURL { return custom }
        #endif
        return defaultSaveDirectory
    }

    public var defaultSaveDirectory: URL {
        StorageLocationResolver.defaultLocalDirectory()
    }

    // MARK: - Theme / launch / search

    public var defaultThemeID: String {
        get { defaults.string(forKey: Key.defaultThemeID) ?? ThemeRegistry.defaultThemeID }
        set { defaults.set(newValue, forKey: Key.defaultThemeID) }
    }

    public var launchBehavior: LaunchBehavior {
        get {
            if defaults.object(forKey: Key.launchBehavior) != nil {
                return LaunchBehavior(rawValue: defaults.integer(forKey: Key.launchBehavior)) ?? .libraryAndRestore
            }
            return .libraryAndRestore
        }
        set { defaults.set(newValue.rawValue, forKey: Key.launchBehavior) }
    }

    public var searchProvider: SearchProvider {
        get {
            guard let raw = defaults.string(forKey: Key.searchProvider),
                  let p = SearchProvider(rawValue: raw) else { return .google }
            return p
        }
        set { defaults.set(newValue.rawValue, forKey: Key.searchProvider) }
    }

    public var homepageURL: URL? {
        get {
            guard let s = defaults.string(forKey: Key.homepageURL), !s.isEmpty else { return nil }
            return URL(string: s)
        }
        set { defaults.set(newValue?.absoluteString, forKey: Key.homepageURL) }
    }

    public var mobileBreakpoint: Double {
        get {
            let v = defaults.double(forKey: Key.mobileBreakpoint)
            return v > 0 ? v : 600
        }
        set { defaults.set(newValue, forKey: Key.mobileBreakpoint) }
    }
}
