import AppKit
import CoreText
import SwiftUI

/// Fjord's look on the app's design (docs/design/fjord): the layout, icons and colours of the design system stay; its
/// neutrals move to the Amont studio's cool ink-and-paper ramp (inverted for light), and the type is Geist and Geist
/// Mono, shipped in the app (Resources/Fonts). Light or dark follows the Mac's appearance at launch;
/// `FJORD_THEME=dark|light` overrides it, and `FJORD_THEME=claude` draws the design system's own values instead.
enum Brand {
    enum Mode { case dark, light, claude }

    static let mode: Mode = switch ProcessInfo.processInfo.environment["FJORD_THEME"] {
    case "dark": .dark
    case "light": .light
    case "claude": .claude
    default: UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
    }
    static var isLight: Bool { mode == .light }
    static var scheme: ColorScheme { isLight ? .light : .dark }
    static var appearance: NSAppearance? { NSAppearance(named: isLight ? .aqua : .darkAqua) }

    /// The ink of "white" text and alpha washes: white on dark, ink on light.
    static var ink: Color { isLight ? map(.white) : .white }

    // MARK: Colour

    private struct RGB { var r, g, b: Double }
    private static let deep = RGB(r: 0x0B / 255, g: 0x0F / 255, b: 0x12 / 255)
    private static let paper = RGB(r: 0xF7 / 255, g: 0xF8 / 255, b: 0xF5 / 255)
    private static let ink0 = RGB(r: 0x10 / 255, g: 0x14 / 255, b: 0x18 / 255)

    static func map(_ color: Color) -> Color {
        guard mode != .claude, let c = NSColor(color).usingColorSpace(.sRGB) else { return color }
        let out = map(RGB(r: c.redComponent, g: c.greenComponent, b: c.blueComponent))
        return Color(.sRGB, red: out.r, green: out.g, blue: out.b, opacity: c.alphaComponent)
    }

    private static func map(_ c: RGB) -> RGB {
        let hi = max(c.r, c.g, c.b), lo = min(c.r, c.g, c.b), l = (hi + lo) / 2
        if hi - lo < 0.09 {
            // a neutral: keep its lightness on the studio ramp; on light, the dark surfaces (t < 0.2) stay within a few
            // steps of paper and text runs from there down to ink
            var t = min(1, max(0, (l - 0.04) / 0.92))
            if isLight { t = t < 0.2 ? 1 - t * 0.35 : 0.93 - (t - 0.2) / 0.8 * 0.9 }
            return mix(deep, paper, t)
        }
        // a colour keeps its hue; on paper the light ones darken so they still read, and the dark tints behind badges
        // and banners become pale washes
        if isLight, l > 0.5 { return mix(c, ink0, 0.32) }
        if isLight, l < 0.35 { return mix(c, paper, 0.84) }
        return c
    }

    private static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
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
        guard mode != .claude, !fontsLoaded else { return }
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
