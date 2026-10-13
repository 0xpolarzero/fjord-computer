import AppKit
import SwiftUI

/// Claude's spark, read from the Claude app the user has installed, so Fjord ships no copy of it (as with its typeface,
/// `ClaudeFonts`): the white spark of its About window's 512px icon (inside its `app.asar`), as a mask, cropped to its rays.
/// Without that, the app's menu bar icon (a small template image); without the app, nil, and an asterisk stands in.
enum ClaudeMark {
    /// Made once, on first use, on whichever thread asks first: `warm()` asks off the main thread at launch, so the first
    /// Open in Claude button drawn doesn't map the 44 MB archive, parse its header and walk the icon's pixels on the main
    /// thread (one drawn before it is done waits for it, rather than making it again).
    static let image: NSImage? = sparkMask() ?? trayIcon()

    /// What the glyphs draw: the spark once `image` is made, published on the main thread, so a glyph drawn before then
    /// shows nothing in its place rather than waiting on the main thread for it.
    @MainActor static let state = Loaded()

    @Observable @MainActor
    final class Loaded {
        /// `image` is made (nil there: no Claude app, the asterisk stands in).
        private(set) var done = false
        private(set) var image: NSImage?
        @ObservationIgnored fileprivate var started = false

        fileprivate func set(_ image: NSImage?) {
            self.image = image
            done = true
        }
    }

    /// Makes `image` in the background, once, and publishes it (`state`).
    @MainActor static func warm() {
        guard !state.started else { return }
        state.started = true
        // Demo and snapshot runs draw it at once, as they are shot.
        if Store.isDemo { return state.set(image) }
        DispatchQueue.global(qos: .utility).async {
            let made = image
            DispatchQueue.main.async { MainActor.assumeIsolated { state.set(made) } }
        }
    }

    /// What `ClaudeButton` and the icon buttons take, in place of a symbol's name, for Open in Claude.
    static let openSymbol = "fjord.open-in-claude"

    /// Claude's clay: the spark's colour, the same in both looks.
    static let clay = Color(.sRGB, red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)

    /// Where the About window's icon is in the app's archive.
    private static let aboutIcon = ".vite/renderer/about_window/assets/icon-"
    /// The mask's side: plenty for a button's icon at any scale.
    private static let side = 128

    private static func sparkMask() -> NSImage? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: ClaudeFonts.asar), options: .alwaysMapped),
              let files = AsarIndex(data),
              let range = files.entries.first(where: { $0.0.hasPrefix(aboutIcon) && $0.0.hasSuffix(".png") })?.1,
              let source = NSBitmapImageRep(data: data.subdata(in: range))?.converting(to: .deviceRGB, renderingIntent: .default),
              source.bitsPerPixel == 32, source.samplesPerPixel == 4, !source.isPlanar, let bytes = source.bitmapData
        else { return nil }
        let w = source.pixelsWide, h = source.pixelsHigh, row = source.bytesPerRow
        // The spark is white on clay: its blue channel tells the two apart (clay's is about a third).
        var alpha = [UInt8](repeating: 0, count: w * h)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let p = y * row + x * 4
                let blue = Double(bytes[p + 2]) / 255, opacity = Double(bytes[p + 3]) / 255
                let a = max(0, min(1, (blue - 0.5) / 0.3)) * opacity
                alpha[y * w + x] = UInt8(a * 255)
                if a > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX > minX, maxY > minY,
              let full = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4,
                                          bitsPerPixel: 32), let out = full.bitmapData else { return nil }
        for i in 0..<(w * h) { out[i * 4 + 3] = alpha[i] }
        // A square around the rays, a little margin kept, drawn down to `side` (the rows run top down; drawing, bottom up).
        let span = max(maxX - minX, maxY - minY) + 6
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let mask = NSImage(size: NSSize(width: side, height: side))
        mask.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        full.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                  from: NSRect(x: cx - span / 2, y: h - cy - span / 2, width: span, height: span),
                  operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        mask.unlockFocus()
        mask.isTemplate = true
        return mask
    }

    private static func trayIcon() -> NSImage? {
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Claude.bundleID)
            ?? URL(fileURLWithPath: "/Applications/Claude.app")
        guard let image = Bundle(url: app)?.image(forResource: "TrayIconTemplate") else { return nil }
        image.isTemplate = true
        return image
    }
}

/// Open in Claude, the same everywhere: Claude's spark, in its clay.
struct OpenInClaudeGlyph: View {
    /// The box it fills, as a symbol's point size.
    var size: CGFloat = 13

    var body: some View {
        let mark = ClaudeMark.state
        Group {
            if !mark.done {
                // Still being made off the main thread: its place, kept.
                Color.clear.onAppear { ClaudeMark.warm() }
            } else if let image = mark.image {
                Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "asterisk").resizable().fontWeight(.bold).aspectRatio(contentMode: .fit)
            }
        }
        .foregroundStyle(ClaudeMark.clay)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A button's icon: a symbol by name, or Open in Claude's glyph for `ClaudeMark.openSymbol`.
struct ButtonIcon: View {
    let name: String
    let size: CGFloat
    var weight: Font.Weight = .regular

    var body: some View {
        if name == ClaudeMark.openSymbol {
            OpenInClaudeGlyph(size: size)
        } else {
            Image(systemName: name).font(.system(size: size, weight: weight))
        }
    }
}
