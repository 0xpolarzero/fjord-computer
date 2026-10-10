import AppKit
import SwiftUI

// How the Router's page is shared between the history (above) and the live zones (Working and Needs you, below), and the
// line between them: drag it, double-click it or click its chevron to switch between the history taking most of the page
// and the zones taking most of it. Neither side goes under its floor, and zones that need less than their share take only
// what they need (the history has the rest).

enum RouterSplit {
    /// The zones' share with the history big, and with the zones big.
    static let historyBig: CGFloat = 0.25
    static let zonesBig: CGFloat = 0.75
    /// Until you set it: the zones may take most of the page (they rarely need it).
    static let initial = zonesBig
    /// What the zones keep however little their share: Needs you's header and a card.
    static let zonesFloor: CGFloat = 120
    /// What a step of the keys (VoiceOver's increment and decrement) moves the line by, as a share of the page.
    static let step: CGFloat = 0.1

    /// What the history keeps however much the zones hold: a few lines at least, more of a tall page.
    static func historyFloor(page height: CGFloat) -> CGFloat { min(height / 2, max(140, height * 0.28)) }

    /// The zones' height between their floor and the history's (the history's wins on a page too short for both).
    static func clamp(_ zones: CGFloat, page height: CGFloat) -> CGFloat {
        let upper = max(0, height - historyFloor(page: height))
        return min(max(zones, min(zonesFloor, upper)), upper)
    }

    /// The most the zones may take for a share.
    static func room(page height: CGFloat, share: CGFloat) -> CGFloat { clamp(share * height, page: height) }

    /// What the zones take: what they need, up to their room.
    static func zones(natural: CGFloat, page height: CGFloat, share: CGFloat) -> CGFloat {
        min(natural, room(page: height, share: share))
    }

    /// The share that gives the zones a height, within the floors.
    static func share(of zones: CGFloat, page height: CGFloat) -> CGFloat {
        height > 0 ? clamp(zones, page: height) / height : initial
    }

    /// The line dragged by `dy` from where it showed the zones `shown` tall (down is positive: the zones shrink).
    static func dragged(from shown: CGFloat, by dy: CGFloat, page height: CGFloat) -> CGFloat {
        share(of: shown - dy, page: height)
    }

    /// Whether the zones take more than the history-big split gives them: the chevron then gives the history the room.
    static func zonesAreBig(shown: CGFloat, page height: CGFloat) -> Bool {
        shown > room(page: height, share: historyBig) + 1
    }

    /// The other snap point from where the line is.
    static func toggled(shown: CGFloat, page height: CGFloat) -> CGFloat {
        zonesAreBig(shown: shown, page: height) ? historyBig : zonesBig
    }

    /// A step up (the zones grow) or down.
    static func adjusted(shown: CGFloat, page height: CGFloat, up: Bool) -> CGFloat {
        share(of: shown + (up ? step : -step) * height, page: height)
    }

    /// The Working card's cap within the zones' room: all of it but the headers with nothing waiting on you, else a part of it
    /// (Needs you takes the rest).
    static func workingCap(room: CGFloat, needsEmpty: Bool) -> CGFloat {
        needsEmpty ? max(88, room - 70) : max(56, room * 0.4)
    }
}

extension Store {
    /// Sets the zones' share of the Router's page, kept across launches.
    func setZonesShare(_ share: CGFloat) {
        var state = router
        state.zonesShare = Double(share)
        router = state
    }
}

/// The line between the history and the zones: a hairline with a generous grip that drags it (double-click switches), and a
/// chevron at its end that switches the split, pointing the way the line will go.
struct RouterDivider: View {
    /// The zones take more than the history-big split: the chevron points down.
    let zonesBig: Bool
    /// The zones' share of the page, as shown.
    let share: CGFloat
    let trailing: CGFloat
    let drag: (CGFloat) -> Void
    let dragEnded: () -> Void
    let toggle: () -> Void
    let adjust: (_ up: Bool) -> Void
    @State private var resizing = false
    @State private var hovered = false

    /// The grip around the line.
    static let grip: CGFloat = 9

    private var label: String { zonesBig ? "Give the history more room" : "Give what's running more room" }

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(CDS.border).frame(height: CDS.hairline)
                .frame(maxWidth: .infinity)
                .frame(height: Self.grip)
                .contentShape(Rectangle())
                .onHover { inside in cursor(inside) }
                .onDisappear { cursor(false) }
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag($0.translation.height) }
                    .onEnded { _ in dragEnded() })
                .onTapGesture(count: 2, perform: toggle)
                .help("Drag to share the page; double-click to switch")
                .accessibilityElement()
                .accessibilityLabel("Split between the history and what's running")
                .accessibilityValue("\(Int((share * 100).rounded())) percent for what's running")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjust(true)
                    case .decrement: adjust(false)
                    @unknown default: break
                    }
                }
            Button(action: toggle) {
                Image(systemName: zonesBig ? "chevron.down" : "chevron.up").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(hovered ? CDS.Text.secondary : CDS.Text.muted)
                    .frame(width: 16, height: 16)
                    .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                        .fill(hovered ? CDS.Fill.ghostHover : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .help(label)
            .accessibilityLabel(label)
        }
        .padding(.trailing, trailing)
        // A hairline in the layout; the grip and the chevron reach over what is above and below it.
        .frame(height: CDS.hairline)
    }

    private func cursor(_ inside: Bool) {
        guard inside != resizing else { return }
        resizing = inside
        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
    }
}
