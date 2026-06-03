import Foundation
import os.log

// MARK: - Logging

/// Centralised loggers shared across macOS and iOS targets.
public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.arjun.Webbed"

    public static let tab     = Logger(subsystem: subsystem, category: "tab")
    public static let persist = Logger(subsystem: subsystem, category: "persistence")
    public static let restore = Logger(subsystem: subsystem, category: "restore")
    public static let window  = Logger(subsystem: subsystem, category: "window")
    public static let web     = Logger(subsystem: subsystem, category: "web")
    public static let sync    = Logger(subsystem: subsystem, category: "sync")
    public static let intent  = Logger(subsystem: subsystem, category: "intent")
}
