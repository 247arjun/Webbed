import Foundation

// MARK: - PersistedRect

/// Codable rectangle used to persist window frames across launches and
/// sync them between macOS devices. Mirrors Noted's `PersistedRect`.
public struct PersistedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public static let `default` = PersistedRect(x: 200, y: 400, width: 1024, height: 720)

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(from rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }
}
