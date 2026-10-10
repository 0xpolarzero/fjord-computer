import AppKit
import CoreText
import SwiftUI

/// Fjord's look on the app's design (docs/design/fjord): the layout, icons and colours of the design system stay; its
/// neutrals move to the Amont studio's cool ink-and-paper ramp (inverted for light), and the type is Geist and Geist
/// Mono, shipped in the app (Resources/Fonts). Every colour carries its light and dark values and follows the Mac's
/// appearance live; `FJORD_THEME=dark|light` pins one, and `FJORD_THEME=claude` draws the design system's own values.
enum Brand {
    enum Mode { case dark, light, claude }

    /// The pinned look, if `FJORD_THEME` sets one; nil follows the Mac.
    static let pinned: Mode? = switch ProcessInfo.processInfo.environment["FJORD_THEME"] {
    case "dark": .dark
    case "light": .light
    case "claude": .claude
    default: nil
    }
    /// The windows' appearance: the pinned one, or nil to inherit the Mac's.
    static var appearance: NSAppearance? {
        switch pinned {
        case .light: NSAppearance(named: .aqua)
        case .dark, .claude: NSAppearance(named: .darkAqua)
        case nil: nil
        }
    }

    /// The ink of "white" text and alpha washes: white on dark, ink on light.
    static let ink: Color = pinned == .claude ? .white : dynamic(dark: RGB(r: 1, g: 1, b: 1), light: map(RGB(r: 1, g: 1, b: 1), light: true), alpha: 1)

    // MARK: Colour

    private struct RGB { var r, g, b: Double }
    private static let deep = RGB(r: 0x0B / 255, g: 0x0F / 255, b: 0x12 / 255)
    private static let paper = RGB(r: 0xF7 / 255, g: 0xF8 / 255, b: 0xF5 / 255)
    private static let ink0 = RGB(r: 0x10 / 255, g: 0x14 / 255, b: 0x18 / 255)

    /// A design-system colour as Fjord draws it: both looks worked out once, the right one picked as it's drawn.
    static func map(_ color: Color) -> Color {
        guard pinned != .claude, let c = NSColor(color).usingColorSpace(.sRGB) else { return color }
        let rgb = RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
        return dynamic(dark: map(rgb, light: false), light: map(rgb, light: true), alpha: c.alphaComponent)
    }

    private static func dynamic(dark: RGB, light: RGB, alpha: Double) -> Color {
        func ns(_ c: RGB) -> NSColor { NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha) }
        switch pinned {
        case .dark: return Color(nsColor: ns(dark))
        case .light: return Color(nsColor: ns(light))
        default:
            let d = ns(dark), l = ns(light)
            return Color(nsColor: NSColor(name: nil) { isDark($0) ? d : l })
        }
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight]).map { $0 == .darkAqua || $0 == .vibrantDark } ?? true
    }

    private static func map(_ c: RGB, light: Bool) -> RGB {
        let hi = max(c.r, c.g, c.b), lo = min(c.r, c.g, c.b), l = (hi + lo) / 2
        let neutral = hi - lo < 0.09
        if !light {
            // dark: a neutral keeps its lightness on the studio ramp; colours are unchanged
            return neutral ? mix(deep, paper, min(1, max(0, (l - 0.04) / 0.92))) : c
        }
        // light: everything keeps the contrast it has against the dark ground, now against paper, so text reads as
        // well as in dark and tints stay as faint. Neutrals take the studio's cool hue; colours keep hue and saturation
        // (capped just above AA, so text reads and the same hue still makes a clean tint).
        let ratio = (luminance(c) + 0.05) / (luminance(darkGround) + 0.05)
        let target = max(luminance(ink0), (luminance(paper) + 0.05) / min(ratio, neutral ? 21 : 4.8) - 0.05)
        var (h, s, _) = hsl(c)
        if neutral { (h, s) = (205, 0.16) }
        return withLuminance(h: h, s: s, target)
    }

    /// The darkest ground of the dark design (CDS surface 0): what paper stands in for.
    private static let darkGround = RGB(r: 0x0B / 255, g: 0x0B / 255, b: 0x0B / 255)

    /// A tint of `color` at `opacity`, as a card's fill: on dark the colour itself made transparent; on light a pale,
    /// opaque colour of the same hue, since a transparent text colour over the ground turns grey.
    static func wash(_ color: Color, _ opacity: Double) -> Color {
        guard pinned != .claude, pinned != .dark else { return color.opacity(opacity) }
        let base = NSColor(color)
        func pale(_ appearance: NSAppearance) -> NSColor {
            var c: NSColor?
            appearance.performAsCurrentDrawingAppearance { c = base.usingColorSpace(.sRGB) }
            guard let c else { return base.withAlphaComponent(opacity) }
            if isDark(appearance) { return c.withAlphaComponent(c.alphaComponent * opacity) }
            let (h, s, _) = hsl(RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent))
            let out = rgb(h: h, s: s, l: 1 - opacity * 0.9)
            return NSColor(srgbRed: out.r, green: out.g, blue: out.b, alpha: 1)
        }
        if pinned == .light, let light = NSAppearance(named: .aqua) { return Color(nsColor: pale(light)) }
        return Color(nsColor: NSColor(name: nil) { pale($0) })
    }

    /// Pins a view's colour scheme when `FJORD_THEME` pins the look; otherwise it follows the window's appearance.
    struct Scheme: ViewModifier {
        func body(content: Content) -> some View {
            switch Brand.pinned {
            case .light: content.environment(\.colorScheme, .light)
            case .dark, .claude: content.environment(\.colorScheme, .dark)
            case nil: content
            }
        }
    }

    private static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }

    private static func luminance(_ c: RGB) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    private static func hsl(_ c: RGB) -> (Double, Double, Double) {
        let hi = max(c.r, c.g, c.b), lo = min(c.r, c.g, c.b), l = (hi + lo) / 2, d = hi - lo
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double = hi == c.r ? (c.g - c.b) / d : hi == c.g ? (c.b - c.r) / d + 2 : (c.r - c.g) / d + 4
        h *= 60
        return (h < 0 ? h + 360 : h, min(1, s), l)
    }

    private static func rgb(h: Double, s: Double, l: Double) -> RGB {
        let c = (1 - abs(2 * l - 1)) * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        return RGB(r: r + m, g: g + m, b: b + m)
    }

    /// The colour of this hue and saturation whose luminance is `target` (lightness found by bisection).
    private static func withLuminance(h: Double, s: Double, _ target: Double) -> RGB {
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if luminance(rgb(h: h, s: s, l: mid)) < target { lo = mid } else { hi = mid }
        }
        return rgb(h: h, s: s, l: (lo + hi) / 2)
    }

    // MARK: Type

    nonisolated(unsafe) private(set) static var fontsLoaded = false

    /// The fonts' folder: the app bundle's Resources/Fonts, or the repository's when run from `swift build`.
    private static var fontsFolder: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Fonts")
    }

    /// Once, at launch: registers Geist and Geist Mono for this process.
    static func loadFonts() {
        guard pinned != .claude, !fontsLoaded else { return }
        for name in ["geist-regular.otf", "geist-medium.otf", "geist-mono.ttf"] {
            let url = fontsFolder.appendingPathComponent(name) as CFURL
            if CTFontManagerRegisterFontsForURL(url, .process, nil) { fontsLoaded = true }
        }
    }

    static func sans(_ size: CGFloat, _ weight: CDS.Weight) -> NSFont? {
        guard fontsLoaded else { return nil }
        return NSFont(name: weight == .regular ? "Geist-Regular" : "Geist-Medium", size: size)
    }

    static func mono(_ size: CGFloat, _ weight: CDS.Weight) -> Font? {
        guard fontsLoaded, let base = NSFont(name: "GeistMono-Regular", size: size) else { return nil }
        let axis = NSNumber(value: 0x7767_6874) // 'wght'
        let w: CGFloat = weight == .regular ? 400 : 500
        return Font(NSFont(descriptor: base.fontDescriptor.addingAttributes([.variation: [axis: w]]), size: size) ?? base)
    }
}
