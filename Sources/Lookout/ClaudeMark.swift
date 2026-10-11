import AppKit
import SwiftUI

/// Claude's spark, as the Claude app the user has installed draws it in the menu bar (its `TrayIconTemplate`, a template
/// image): read from the app, so Lookout ships no copy of it, as with its typeface (`ClaudeFonts`). Without the app, an
/// asterisk stands in.
enum ClaudeMark {
    @MainActor static let image: NSImage? = {
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Claude.bundleID)
            ?? URL(fileURLWithPath: "/Applications/Claude.app")
        guard let image = Bundle(url: app)?.image(forResource: "TrayIconTemplate") else { return nil }
        image.isTemplate = true
        return image
    }()

    /// What `ClaudeButton` and the icon buttons take, in place of a symbol's name, for Open in Claude.
    static let openSymbol = "lookout.open-in-claude"
}

/// Open in Claude, the same everywhere: Claude's spark with an arrow at its top right corner. The spark is round, so a
/// spark in the bottom left two thirds leaves that corner free for the arrow: they never touch, and nothing is masked.
/// Drawn in the foreground style, like a symbol.
struct OpenInClaudeGlyph: View {
    /// The box it fills, as a symbol's point size.
    var size: CGFloat = 13

    /// How much of the Claude app's image the spark fills (it is padded all round).
    private static let inked: CGFloat = 50.0 / 72

    var body: some View {
        let mark = size * 0.7, arrow = size * 0.42
        ZStack(alignment: .bottomLeading) {
            Color.clear
            // The image is larger than the spark by its padding: drawn that much larger, centred on the spark's box.
            spark
                .frame(width: mark / Self.inked, height: mark / Self.inked)
                .frame(width: mark, height: mark)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.right").font(.system(size: arrow, weight: .bold))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var spark: some View {
        if let image = ClaudeMark.image {
            Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "asterisk").resizable().fontWeight(.bold).aspectRatio(contentMode: .fit)
        }
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
