import Foundation

// MARK: - ChromeLayoutMetrics

/// Breakpoint constants for the responsive macOS chrome. Centralised so the
/// thresholds are tunable in one place.
enum ChromeLayoutMetrics {
    /// Below this width, drop back/forward/reload from the visible chrome;
    /// also flip the WKWebView to a mobile UA.
    static let compactWidthThreshold: CGFloat = 600
    /// Below this width, collapse the URL display to host-only.
    static let tinyWidthThreshold: CGFloat = 360
    /// Below this height, shrink the header band.
    static let ultraTinyHeightThreshold: CGFloat = 220

    /// Standard / compact header heights.
    static let headerHeight: CGFloat = 38
    static let headerHeightUltraTiny: CGFloat = 28

    /// Chrome density label for the current size.
    enum Mode { case desktop, compact, tiny }

    static func mode(forWidth w: CGFloat) -> Mode {
        if w < tinyWidthThreshold        { return .tiny }
        if w < compactWidthThreshold     { return .compact }
        return .desktop
    }

    /// Mobile Safari UA — used below `compactWidthThreshold` so responsive
    /// sites render their mobile layout.
    static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}
