import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - WebbedTheme

/// Chrome accent + body palette for a tab window / tab editor.
public struct WebbedTheme: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let bodyBackgroundColor: PlatformColor
    public let headerBackgroundColor: PlatformColor
    public let titleTextColor: PlatformColor
    public let bodyTextColor: PlatformColor
    public let placeholderTextColor: PlatformColor
    public let controlTintColor: PlatformColor
    /// True ⇒ the chrome uses a system blur material (NSVisualEffectView /
    /// UIVisualEffectView) rather than a flat fill.
    public let chromeBlur: Bool

    public init(
        id: String,
        displayName: String,
        bodyBackgroundColor: PlatformColor,
        headerBackgroundColor: PlatformColor,
        titleTextColor: PlatformColor,
        bodyTextColor: PlatformColor,
        placeholderTextColor: PlatformColor,
        controlTintColor: PlatformColor,
        chromeBlur: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.bodyBackgroundColor = bodyBackgroundColor
        self.headerBackgroundColor = headerBackgroundColor
        self.titleTextColor = titleTextColor
        self.bodyTextColor = bodyTextColor
        self.placeholderTextColor = placeholderTextColor
        self.controlTintColor = controlTintColor
        self.chromeBlur = chromeBlur
    }
}

// MARK: - ThemeRegistry

public enum ThemeRegistry {

    public static let defaultThemeID = "graphite"

    public static let allThemes: [WebbedTheme] = [graphite, aqua, pumpkin, forest, rose]

    public static func theme(for id: String) -> WebbedTheme {
        allThemes.first(where: { $0.id == id }) ?? graphite
    }

    // MARK: Built-in themes

    public static let graphite = WebbedTheme(
        id: "graphite",
        displayName: "Graphite",
        bodyBackgroundColor:   .rgb(0.97, 0.97, 0.98),
        headerBackgroundColor: .rgb(0.92, 0.92, 0.94),
        titleTextColor:        .rgb(0.10, 0.10, 0.12),
        bodyTextColor:         .rgb(0.13, 0.13, 0.13),
        placeholderTextColor:  .rgb(0.45, 0.45, 0.50),
        controlTintColor:      .rgb(0.20, 0.20, 0.24),
        chromeBlur:            true
    )

    public static let aqua = WebbedTheme(
        id: "aqua",
        displayName: "Aqua",
        bodyBackgroundColor:   .rgb(0.93, 0.97, 1.00),
        headerBackgroundColor: .rgb(0.52, 0.78, 0.96),
        titleTextColor:        .rgb(0.05, 0.18, 0.32),
        bodyTextColor:         .rgb(0.10, 0.14, 0.20),
        placeholderTextColor:  .rgb(0.30, 0.45, 0.60),
        controlTintColor:      .rgb(0.08, 0.30, 0.55),
        chromeBlur:            false
    )

    public static let pumpkin = WebbedTheme(
        id: "pumpkin",
        displayName: "Pumpkin",
        bodyBackgroundColor:   .rgb(1.00, 0.95, 0.88),
        headerBackgroundColor: .rgb(0.98, 0.62, 0.25),
        titleTextColor:        .rgb(0.35, 0.15, 0.04),
        bodyTextColor:         .rgb(0.20, 0.12, 0.06),
        placeholderTextColor:  .rgb(0.55, 0.35, 0.18),
        controlTintColor:      .rgb(0.45, 0.20, 0.05),
        chromeBlur:            false
    )

    public static let forest = WebbedTheme(
        id: "forest",
        displayName: "Forest",
        bodyBackgroundColor:   .rgb(0.93, 0.97, 0.93),
        headerBackgroundColor: .rgb(0.40, 0.62, 0.42),
        titleTextColor:        .rgb(0.07, 0.20, 0.08),
        bodyTextColor:         .rgb(0.10, 0.18, 0.10),
        placeholderTextColor:  .rgb(0.32, 0.48, 0.32),
        controlTintColor:      .rgb(0.12, 0.32, 0.14),
        chromeBlur:            false
    )

    public static let rose = WebbedTheme(
        id: "rose",
        displayName: "Rose",
        bodyBackgroundColor:   .rgb(1.00, 0.94, 0.95),
        headerBackgroundColor: .rgb(0.96, 0.62, 0.70),
        titleTextColor:        .rgb(0.35, 0.08, 0.15),
        bodyTextColor:         .rgb(0.18, 0.10, 0.12),
        placeholderTextColor:  .rgb(0.60, 0.35, 0.42),
        controlTintColor:      .rgb(0.45, 0.12, 0.22),
        chromeBlur:            false
    )
}
