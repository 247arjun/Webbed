import Foundation

#if canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformImage = UIImage
#endif

// MARK: - Color helpers

public extension PlatformColor {
    /// Convenience constructor that's identical between NSColor and UIColor.
    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) -> PlatformColor {
        PlatformColor(red: r, green: g, blue: b, alpha: a)
    }
}
