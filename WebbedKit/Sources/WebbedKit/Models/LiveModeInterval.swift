import Foundation

// MARK: - LiveModeInterval

/// Per-window auto-refresh cadence. Stored on each `TabRecord` so the choice
/// persists across launches and syncs with iCloud.
public enum LiveModeInterval: Int, Codable, CaseIterable, Sendable, Identifiable {
    case off    = 0
    case s5     = 5
    case s10    = 10
    case s30    = 30
    case s60    = 60
    case s300   = 300
    case s600   = 600
    case s1800  = 1800

    public var id: Int { rawValue }

    public var seconds: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue)
    }

    public var displayName: String {
        switch self {
        case .off:    return "Off"
        case .s5:     return "Every 5 seconds"
        case .s10:    return "Every 10 seconds"
        case .s30:    return "Every 30 seconds"
        case .s60:    return "Every minute"
        case .s300:   return "Every 5 minutes"
        case .s600:   return "Every 10 minutes"
        case .s1800:  return "Every 30 minutes"
        }
    }

    /// Compact label for the chrome ("5s", "30s", "1m", "5m"...).
    public var shortLabel: String {
        switch self {
        case .off:    return "Off"
        case .s5:     return "5s"
        case .s10:    return "10s"
        case .s30:    return "30s"
        case .s60:    return "1m"
        case .s300:   return "5m"
        case .s600:   return "10m"
        case .s1800:  return "30m"
        }
    }
}
