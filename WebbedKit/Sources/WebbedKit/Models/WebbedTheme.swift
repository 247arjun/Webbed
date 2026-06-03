import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - WebbedTheme

/// Chrome palette for a single tab window. Two shapes:
/// * `.system()` — neutral chrome that picks up the OS appearance and adapts
///   between light and dark mode automatically.
/// * `.color(...)` — chrome synthesized from a single base color (page
///   `theme-color` meta or sampled favicon). Text colors are chosen for
///   WCAG contrast against the base; control tint is a saturation-boosted
///   variant of the base.
public struct WebbedTheme: Equatable, Sendable {
    public let bodyBackgroundColor: PlatformColor
    public let headerBackgroundColor: PlatformColor
    public let titleTextColor: PlatformColor
    public let bodyTextColor: PlatformColor
    public let placeholderTextColor: PlatformColor
    public let controlTintColor: PlatformColor
    public let isSynthesized: Bool

    public init(
        bodyBackgroundColor: PlatformColor,
        headerBackgroundColor: PlatformColor,
        titleTextColor: PlatformColor,
        bodyTextColor: PlatformColor,
        placeholderTextColor: PlatformColor,
        controlTintColor: PlatformColor,
        isSynthesized: Bool = false
    ) {
        self.bodyBackgroundColor   = bodyBackgroundColor
        self.headerBackgroundColor = headerBackgroundColor
        self.titleTextColor        = titleTextColor
        self.bodyTextColor         = bodyTextColor
        self.placeholderTextColor  = placeholderTextColor
        self.controlTintColor      = controlTintColor
        self.isSynthesized         = isSynthesized
    }

    // MARK: - Factories

    /// Neutral chrome that follows the system appearance.
    public static func system() -> WebbedTheme {
        #if canImport(AppKit)
        return WebbedTheme(
            bodyBackgroundColor:   .windowBackgroundColor,
            headerBackgroundColor: .underPageBackgroundColor,
            titleTextColor:        .labelColor,
            bodyTextColor:         .labelColor,
            placeholderTextColor:  .placeholderTextColor,
            controlTintColor:      .controlAccentColor,
            isSynthesized:         false
        )
        #elseif canImport(UIKit)
        return WebbedTheme(
            bodyBackgroundColor:   .systemBackground,
            headerBackgroundColor: .secondarySystemBackground,
            titleTextColor:        .label,
            bodyTextColor:         .label,
            placeholderTextColor:  .placeholderText,
            controlTintColor:      .tintColor,
            isSynthesized:         false
        )
        #endif
    }

    /// Synthesize a chrome palette from a single base color (typically the
    /// page's `theme-color` meta or a sampled favicon hue).
    public static func color(from base: PlatformColor) -> WebbedTheme {
        let text          = DominantColor.contrastingText(for: base)
        let textIsDark    = text == PlatformColor(red: 0, green: 0, blue: 0, alpha: 1)
        let body          = mix(base, with: textIsDark ? .white : .black, fraction: 0.85)
        let placeholder   = text.withAlphaComponent(0.55)
        let controlTint   = textIsDark ? darken(base, by: 0.25) : lighten(base, by: 0.25)
        return WebbedTheme(
            bodyBackgroundColor:   body,
            headerBackgroundColor: base,
            titleTextColor:        text,
            bodyTextColor:         textIsDark ? .black : .white,
            placeholderTextColor:  placeholder,
            controlTintColor:      controlTint,
            isSynthesized:         true
        )
    }

    // MARK: - Color helpers

    private static func mix(_ a: PlatformColor, with b: PlatformColor, fraction: CGFloat) -> PlatformColor {
        // fraction = 0 → all a; fraction = 1 → all b.
        let f = max(0, min(1, fraction))
        let (ar, ag, ab, aa) = components(a)
        let (br, bg, bb, ba) = components(b)
        return PlatformColor(
            red:   ar * (1 - f) + br * f,
            green: ag * (1 - f) + bg * f,
            blue:  ab * (1 - f) + bb * f,
            alpha: aa * (1 - f) + ba * f
        )
    }

    private static func lighten(_ color: PlatformColor, by amount: CGFloat) -> PlatformColor {
        mix(color, with: .white, fraction: amount)
    }

    private static func darken(_ color: PlatformColor, by amount: CGFloat) -> PlatformColor {
        mix(color, with: .black, fraction: amount)
    }

    private static func components(_ c: PlatformColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        #if canImport(AppKit)
        let converted = c.usingColorSpace(.sRGB) ?? c
        return (converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent)
        #elseif canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if c.getRed(&r, green: &g, blue: &b, alpha: &a) { return (r, g, b, a) }
        return (0, 0, 0, 1)
        #endif
    }
}

private extension PlatformColor {
    static var white: PlatformColor { PlatformColor(red: 1, green: 1, blue: 1, alpha: 1) }
    static var black: PlatformColor { PlatformColor(red: 0, green: 0, blue: 0, alpha: 1) }
}
