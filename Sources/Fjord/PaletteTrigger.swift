import SwiftUI

extension EnvironmentValues {
    /// Opens the palette over the window (the header's trigger).
    @Entry var openPalette: () -> Void = {}
}

/// The header's way into the palette, where the page searches' fields were: the same 200 × 26 pill with a magnifier and a
/// muted "Search", and the palette's shortcut as keycaps at its end. A click opens the palette.
struct PaletteTrigger: View {
    @Environment(\.openPalette) private var open
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CDS.Text.muted)
                Text("Search").font(CDS.sans(CDS.Sidebar.rowFont)).foregroundStyle(CDS.Text.muted).lineLimit(1)
                Spacer(minLength: 0)
                Keycaps(caps: Palette.shortcut.caps, ink: CDS.Keycap.ink)
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(width: 200, height: 26)
            .background(Theme.Radius.shape(CDS.Sidebar.radius).fill(hover ? CDS.Fill.secondaryHover : CDS.Fill.field))
            .overlay(Theme.Radius.shape(CDS.Sidebar.radius).strokeBorder(CDS.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Search · \(Palette.shortcut.display)")
        .accessibilityLabel("Search")
        .accessibilityHint("Opens the search, \(Palette.shortcut.display)")
    }
}
