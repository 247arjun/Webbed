import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - DominantColor

/// Tools for deriving a tab's chrome color from page hints or favicon pixels.
public enum DominantColor {

    // MARK: - RGBA <-> Data

    /// Pack an RGBA color into the 4-byte `Data` blob stored on TabRecord.
    public static func data(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) -> Data {
        Data([red, green, blue, alpha])
    }

    public static func data(from color: PlatformColor) -> Data? {
        guard let (r, g, b, a) = rgba(of: color) else { return nil }
        return data(red: r, green: g, blue: b, alpha: a)
    }

    public static func color(from data: Data?) -> PlatformColor? {
        guard let data, data.count >= 3 else { return nil }
        let r = CGFloat(data[0]) / 255
        let g = CGFloat(data[1]) / 255
        let b = CGFloat(data[2]) / 255
        let a = data.count >= 4 ? CGFloat(data[3]) / 255 : 1
        return PlatformColor(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Parsing CSS color strings (theme-color meta values)

    /// Parse a CSS color string (`#abc`, `#aabbcc`, `rgb(...)`, `rgba(...)`).
    /// HSL and named colors are intentionally not supported — pages that use
    /// those for theme-color are vanishingly rare; we'd rather fall back to
    /// favicon sampling than ship a 200-LOC parser.
    public static func parseCSS(_ string: String) -> PlatformColor? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }

        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            return parseHex(hex)
        }
        if s.hasPrefix("rgb") {
            // rgb(r, g, b) or rgba(r, g, b, a)
            if let openIdx = s.firstIndex(of: "("),
               let closeIdx = s.lastIndex(of: ")") {
                let inner = s[s.index(after: openIdx)..<closeIdx]
                let parts = inner.split(whereSeparator: { ",/ ".contains($0) })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 3,
                      let r = parseChannel(parts[0]),
                      let g = parseChannel(parts[1]),
                      let b = parseChannel(parts[2]) else { return nil }
                let a: UInt8 = parts.count >= 4 ? parseAlpha(parts[3]) ?? 255 : 255
                return PlatformColor(red: CGFloat(r)/255,
                                     green: CGFloat(g)/255,
                                     blue:  CGFloat(b)/255,
                                     alpha: CGFloat(a)/255)
            }
        }
        // A handful of common named colors — cheap to support.
        switch s {
        case "black":  return PlatformColor(red: 0, green: 0, blue: 0, alpha: 1)
        case "white":  return PlatformColor(red: 1, green: 1, blue: 1, alpha: 1)
        default: return nil
        }
    }

    private static func parseHex(_ hex: String) -> PlatformColor? {
        let cleaned = hex.trimmingCharacters(in: .whitespaces)
        let expanded: String
        switch cleaned.count {
        case 3: // #abc → #aabbcc
            expanded = cleaned.map { "\($0)\($0)" }.joined()
        case 4: // #abcd → #aabbccdd
            expanded = cleaned.map { "\($0)\($0)" }.joined()
        case 6, 8:
            expanded = cleaned
        default: return nil
        }
        var value: UInt64 = 0
        guard Scanner(string: expanded).scanHexInt64(&value) else { return nil }
        if expanded.count == 6 {
            return PlatformColor(
                red:   CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8)  & 0xFF) / 255,
                blue:  CGFloat( value        & 0xFF) / 255,
                alpha: 1
            )
        } else {
            return PlatformColor(
                red:   CGFloat((value >> 24) & 0xFF) / 255,
                green: CGFloat((value >> 16) & 0xFF) / 255,
                blue:  CGFloat((value >> 8)  & 0xFF) / 255,
                alpha: CGFloat( value        & 0xFF) / 255
            )
        }
    }

    private static func parseChannel(_ s: String) -> Int? {
        if s.hasSuffix("%") {
            guard let pct = Double(s.dropLast()) else { return nil }
            return max(0, min(255, Int(pct / 100 * 255)))
        }
        return Int(s).map { max(0, min(255, $0)) }
    }

    private static func parseAlpha(_ s: String) -> UInt8? {
        if s.hasSuffix("%") {
            guard let pct = Double(s.dropLast()) else { return nil }
            return UInt8(max(0, min(255, Int(pct / 100 * 255))))
        }
        if let d = Double(s) {
            return UInt8(max(0, min(255, Int(d * 255))))
        }
        return nil
    }

    // MARK: - Favicon sampling

    /// Pick a representative color from `image`. Returns nil for grayscale
    /// icons (low chroma) so the caller can fall back to the default theme
    /// rather than producing mud.
    @MainActor
    public static func sample(from image: PlatformImage) -> PlatformColor? {
        guard let pixels = rgbaPixels(downscaling: image, to: 24) else { return nil }
        // (hueBucket, satBucket, valBucket) -> (count, summedR, summedG, summedB)
        struct Bucket { var count = 0; var r = 0; var g = 0; var b = 0 }
        var buckets: [String: Bucket] = [:]
        var anyChroma = false

        var i = 0
        while i + 3 < pixels.count {
            let r = pixels[i], g = pixels[i+1], b = pixels[i+2], a = pixels[i+3]
            i += 4
            if a < 100 { continue }
            // Skip near-white and near-black.
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            if maxC > 240 && minC > 220 { continue }
            if maxC < 32 { continue }
            // Skip near-grays.
            let chroma = Int(maxC) - Int(minC)
            if chroma < 20 { continue }
            anyChroma = true

            let (h, s, v) = hsv(r: r, g: g, b: b)
            // Coarse quantize: 12 hue × 4 sat × 4 value buckets.
            let key = "\(h/30)|\(s/64)|\(v/64)"
            var entry = buckets[key] ?? Bucket()
            entry.count += 1
            entry.r += Int(r); entry.g += Int(g); entry.b += Int(b)
            buckets[key] = entry
        }

        guard anyChroma, let top = buckets.values.max(by: { $0.count < $1.count }) else {
            return nil
        }
        let r = top.r / top.count
        let g = top.g / top.count
        let b = top.b / top.count
        return PlatformColor(red:   CGFloat(r) / 255,
                             green: CGFloat(g) / 255,
                             blue:  CGFloat(b) / 255,
                             alpha: 1)
    }

    // MARK: - Pixel access

    /// Downscale the image to roughly `target × target` and return interleaved
    /// RGBA bytes. Returns nil if a context can't be created.
    @MainActor
    private static func rgbaPixels(downscaling image: PlatformImage, to target: Int) -> [UInt8]? {
        #if canImport(AppKit)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return drawAndExtract(cg: cg, target: target)
        #elseif canImport(UIKit)
        guard let cg = image.cgImage else { return nil }
        return drawAndExtract(cg: cg, target: target)
        #endif
    }

    private static func drawAndExtract(cg: CGImage, target: Int) -> [UInt8]? {
        let w = target
        let h = target
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: w * h * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &bytes,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }

    // MARK: - HSV conversion

    private static func hsv(r: UInt8, g: UInt8, b: UInt8) -> (h: Int, s: Int, v: Int) {
        let rf = Double(r), gf = Double(g), bf = Double(b)
        let maxV = max(rf, max(gf, bf))
        let minV = min(rf, min(gf, bf))
        let delta = maxV - minV
        var h: Double = 0
        if delta > 0 {
            if maxV == rf { h = 60 * ((gf - bf) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxV == gf { h = 60 * (((bf - rf) / delta) + 2) }
            else               { h = 60 * (((rf - gf) / delta) + 4) }
            if h < 0 { h += 360 }
        }
        let s = maxV == 0 ? 0 : delta / maxV * 255
        return (Int(h), Int(s), Int(maxV))
    }

    // MARK: - PlatformColor → RGBA bytes

    private static func rgba(of color: PlatformColor) -> (UInt8, UInt8, UInt8, UInt8)? {
        #if canImport(AppKit)
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        let r = UInt8(max(0, min(255, converted.redComponent   * 255)))
        let g = UInt8(max(0, min(255, converted.greenComponent * 255)))
        let b = UInt8(max(0, min(255, converted.blueComponent  * 255)))
        let a = UInt8(max(0, min(255, converted.alphaComponent * 255)))
        return (r, g, b, a)
        #elseif canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (
            UInt8(max(0, min(255, r * 255))),
            UInt8(max(0, min(255, g * 255))),
            UInt8(max(0, min(255, b * 255))),
            UInt8(max(0, min(255, a * 255)))
        )
        #endif
    }

    // MARK: - WCAG contrast

    /// Returns either pure black or pure white depending on which gives
    /// better contrast against `color`. Used to pick legible text colors.
    public static func contrastingText(for color: PlatformColor) -> PlatformColor {
        let lum = relativeLuminance(color)
        return lum > 0.5
            ? PlatformColor(red: 0, green: 0, blue: 0, alpha: 1)
            : PlatformColor(red: 1, green: 1, blue: 1, alpha: 1)
    }

    private static func relativeLuminance(_ color: PlatformColor) -> Double {
        guard let (r, g, b, _) = rgba(of: color) else { return 0.5 }
        func channel(_ v: UInt8) -> Double {
            let s = Double(v) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}
