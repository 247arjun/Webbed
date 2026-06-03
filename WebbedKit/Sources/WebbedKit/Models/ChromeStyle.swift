import Foundation

// MARK: - ChromeStyle

/// Top-level appearance choice for tab windows.
public enum ChromeStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Chrome adapts to each page (via theme-color meta or sampled favicon).
    case color
    /// Neutral chrome that follows the system appearance, no per-page tinting.
    case system

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .color:  return "Color"
        case .system: return "System"
        }
    }

    public var blurb: String {
        switch self {
        case .color:  return "Tints each window using the site's theme color or favicon."
        case .system: return "Neutral chrome that follows your macOS / iOS appearance."
        }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted whenever `AppSettings.chromeStyle` changes so live windows
    /// can re-pick their chrome.
    static let webbedChromeStyleChanged = Notification.Name("webbedChromeStyleChanged")
}
