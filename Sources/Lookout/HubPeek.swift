import SwiftUI

// Hovering a section of the bar opens just that section beside it, in a panel lined up with its cells. The bar
// itself never moves, so what you're pointing at stays under the pointer. A click goes to the app window.

enum HubSection: Hashable { case inbox, router, controls }

struct PeekMeasure: Equatable {
    let section: HubSection
    let size: CGSize
}

/// Reports a section's place in the bar and makes it the one shown when the pointer enters it.
struct SectionProbe: ViewModifier {
    let section: HubSection
    let hub: HubState
    @Binding var frames: [HubSection: CGRect]

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LookoutHub.barSpace)) } action: { frame in
                if frames[section] != frame { frames[section] = frame }
            }
            .onHover { if $0 { hub.enter(section) } else { hub.cancelDwell() } }
    }
}

extension LookoutHub {
    static let barSpace = "hub-bar"
    /// Between the bar and a section's panel: none, so the pointer never falls between them.
    static let peekGap: CGFloat = 0

    func probe(_ section: HubSection) -> SectionProbe {
        SectionProbe(section: section, hub: hub, frames: $sectionFrames)
    }

    /// The hovered section.
    var peeking: HubSection? { hub.quiet ? nil : hub.section }

    /// Where a panel sits along the bar: from `start`, `length` long (both along the bar's edge), and which of the
    /// bar's ends it reaches.
    struct Placement: Equatable {
        var start: CGFloat
        var length: CGFloat
        /// Flush with the bar's start (top, or left), or reaching its end (bottom, or right): the bar's corner there
        /// goes square, so the two make one clean edge.
        var atStart: Bool
        var atEnd: Bool
        /// Runs on past the bar's end: its own corner there stays round.
        var pastEnd: Bool
    }

    /// Closer than this to an end of the bar, a panel snaps flush with it.
    static let peekSnap: CGFloat = 60

    /// Beside the bar, a panel's header lines up with its section's first cell (the inbox's starts at the bar's
    /// top, the controls' ends at its bottom); along the top and bottom it starts under its segment (ends under it,
    /// for the controls). Then it's kept within the bar, and snapped flush with an end it comes close to.
    func placement(_ section: HubSection, _ frame: CGRect) -> Placement? {
        let bar = edge.isHorizontal ? barSize.width : barSize.height
        // This section's own measured size: until it's known (or while another's is all there is), nothing to place.
        let natural = edge.isHorizontal ? panelWidth(section) : peekSizes[section]?.height ?? 0
        guard bar > 0, natural > 0, peekSizes[section] != nil else { return nil }
        var start: CGFloat
        var length = natural
        if edge.isHorizontal {
            start = section == .controls ? frame.maxX - length : frame.minX
            start = min(max(start, 0), max(bar - length, 0))
            if start < Self.peekSnap { start = 0 }
            if length <= bar, bar - (start + length) < Self.peekSnap { start = bar - length }
        } else {
            // Its lines stay level with their cells, so it only moves at the ends: it grows to meet the bar's
            // bottom if it ends close to it.
            start = section == .inbox ? 0 : section == .controls ? bar - length : max(frame.minY - Self.peekPad, 0)
            let short = bar - (start + length)
            if short >= 0, short < Self.peekSnap { length = bar - start }
        }
        let end = start + length
        return Placement(start: start, length: length, atStart: start <= 0.5, atEnd: end >= bar - 0.5, pastEnd: end > bar + 0.5)
    }

    /// The panel for the hovered section, placed beside (or under) its cells in the bar.
    @ViewBuilder var peekPanel: some View {
        if let section = peeking, let frame = sectionFrames[section] {
            let place = placement(section, frame)
            let shape = panelShape(place)
            let panel = peekContent(section)
                // The section is part of what's observed: an equal size on switching must still fill that section's entry.
                .onGeometryChange(for: PeekMeasure.self) { PeekMeasure(section: section, size: $0.size) } action: {
                    if peekSizes[$0.section] != $0.size { peekSizes[$0.section] = $0.size }
                }
                .frame(height: edge.isHorizontal ? nil : place?.length, alignment: .top)
                .background(shape.fill(Theme.bg))
                .overlay(shape.strokeBorder(CDS.border, lineWidth: 1))
                .clipShape(shape)
                // No seam where it meets the bar: the two outlines there are painted over, so bar and panel read
                // as one shape.
                .overlay(alignment: seamAlignment) { seam(place) }
                .fixedSize()
                .onHover { overPanel = $0; hoverChanged() }
                // Only the current section's: one still fading out mustn't report where it was.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.rootSpace)) } action: {
                    if hub.section == section { hub.panelFrame = $0 }
                }
                // Hidden until it's been measured and placed, so it never shows up in the wrong spot first.
                .opacity(place == nil ? 0 : 1)
                .transition(peekTransition)
            let o = peekOffset(section, place)
            panel.offset(x: o.width, y: o.height)
        }
    }

    /// Only the first open and the last close fade and slide; switching sections is instant (no Reduce Motion: no slide).
    var peekTransition: AnyTransition {
        let d: CGFloat = reduce ? 0 : Theme.Space.sm
        return .opacity.combined(with: .offset(x: edge == .right ? d : edge == .left ? -d : 0,
                                               y: edge == .top ? -d : edge == .bottom ? d : 0))
    }

    /// Laid over the bar from its top-left (bottom-left on the bottom edge), then moved out beside it.
    func peekOffset(_ section: HubSection, _ place: Placement?) -> CGSize {
        let along = place?.start ?? 0
        return switch edge {
        case .right: CGSize(width: -(panelWidth(section) + Self.peekGap), height: along)
        case .left: CGSize(width: Self.cell + Self.peekGap, height: along)
        case .top: CGSize(width: along, height: Self.cell + Self.peekGap)
        case .bottom: CGSize(width: along, height: -(Self.cell + Self.peekGap))
        }
    }

    /// The open panel's outline with its shadow, in the layer behind the bar and panel.
    @ViewBuilder var peekShadow: some View {
        if let section = peeking, let frame = sectionFrames[section], let place = placement(section, frame),
           let size = peekSizes[section] {
            let o = peekOffset(section, place)
            Color.clear
                .frame(width: panelWidth(section), height: edge.isHorizontal ? size.height : place.length)
                // Claude's `shadow-panel` drops.
                .background {
                    panelShape(place).fill(Theme.bg)
                        .shadow(color: CDS.PanelShadow.far.color, radius: CDS.PanelShadow.far.radius, y: CDS.PanelShadow.far.y)
                        .shadow(color: CDS.PanelShadow.near.color, radius: CDS.PanelShadow.near.radius, y: CDS.PanelShadow.near.y)
                }
                .offset(x: o.width, y: o.height)
                .transition(peekTransition)
        }
    }

    /// Where the panel hangs from: the bar's top-left, or its bottom-left on the bottom edge.
    var peekAlignment: Alignment { edge == .bottom ? .bottomLeading : .topLeading }

    /// The current panel's place, for the bar's own outline.
    var currentPlacement: Placement? {
        guard let section = peeking, let frame = sectionFrames[section] else { return nil }
        return placement(section, frame)
    }

    var seamAlignment: Alignment {
        switch edge {
        case .right: .topTrailing
        case .left: .topLeading
        case .top: .topLeading
        case .bottom: .bottomLeading
        }
    }

    /// Paint over both outlines along what the panel shares with the bar (1pt into each), short of its ends so
    /// the panel's own outline still meets the bar there; not past the bar's end, where the panel's edge is its own.
    func seam(_ place: Placement?) -> some View {
        let bar = edge.isHorizontal ? barSize.width : barSize.height
        let shared = place.map { max(0, min($0.start + $0.length, bar) - $0.start - 2) } ?? 0
        return Rectangle().fill(Theme.bg)
            .frame(width: edge.isHorizontal ? shared : 2, height: edge.isHorizontal ? 2 : shared)
            .offset(x: edge == .right ? 1 : edge == .left ? -1 : 1, y: edge == .top ? -1 : edge == .bottom ? 1 : 1)
    }

    /// The bar's outline: a corner goes square where a panel is flush with (or runs past) that end of the bar.
    var barOutline: UnevenRoundedRectangle {
        let r: CGFloat = 20
        let place = currentPlacement
        let start: CGFloat = place?.atStart == true ? 0 : r
        let end: CGFloat = place?.atEnd == true ? 0 : r
        return switch edge {
        case .right: UnevenRoundedRectangle(topLeadingRadius: start, bottomLeadingRadius: end, style: .continuous)
        case .left: UnevenRoundedRectangle(bottomTrailingRadius: end, topTrailingRadius: start, style: .continuous)
        case .top: UnevenRoundedRectangle(bottomLeadingRadius: start, bottomTrailingRadius: end, style: .continuous)
        case .bottom: UnevenRoundedRectangle(topLeadingRadius: start, topTrailingRadius: end, style: .continuous)
        }
    }

    /// A panel against the bar: square where it meets the bar, rounded elsewhere, and rounded on the bar's side too
    /// where it runs on past the bar's end.
    func panelShape(_ place: Placement?) -> UnevenRoundedRectangle {
        let r = Self.panelRadius
        let past: CGFloat = place?.pastEnd == true ? r : 0
        return switch edge {
        case .right: UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: past, style: .continuous)
        case .left: UnevenRoundedRectangle(bottomLeadingRadius: past, bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
        case .top: UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: past, style: .continuous)
        case .bottom: UnevenRoundedRectangle(topLeadingRadius: r, bottomTrailingRadius: past, topTrailingRadius: r, style: .continuous)
        }
    }

    /// A panel's free corners: the hub's shell round, larger than Claude's 10pt popovers as it is part of the island.
    static let panelRadius: CGFloat = 16
    /// A panel's padding, all round, as Claude's sidebar body (8 at the sides); rows pad their own inside it.
    static let peekPad: CGFloat = Theme.Space.md
    /// A section header's height, the same as a CI or agents cell in the bar, so the lines under it line up.
    static let peekLine: CGFloat = Theme.Metrics.line

    /// A panel's width: the controls' is a small menu.
    func panelWidth(_ section: HubSection) -> CGFloat {
        section == .controls ? Self.controlsWidth : Self.detail
    }

    /// The controls' panel: a Claude menu's width (128–320).
    static let controlsWidth: CGFloat = 232

    @ViewBuilder func peekContent(_ section: HubSection) -> some View {
        Group {
            if section == .controls { peekControls }
            else if edge.isHorizontal { peekColumn(section) } else { peekRows(section) }
        }
        // The controls are a menu: Claude's `p-1` around its rows (and 2 more, for the panel's larger round).
        .padding(section == .controls ? CDS.Menu.pad + 2 : Self.peekPad)
        .frame(width: panelWidth(section))
    }

    /// Beside the bar: the header level with the section's first cell, then one line per cell, as tall as the
    /// cell; then whatever only the panel has (the inbox list).
    @ViewBuilder func peekRows(_ section: HubSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch section {
            case .inbox:
                inboxHeader.frame(height: Self.peekLine)
                peekInbox.padding(.top, 4)
            case .router:
                peekRouter
            default:
                // (The controls have their own panel.)
                EmptyView()
            }
        }
        .frame(width: Self.detail - 2 * Self.peekPad, alignment: .leading)
    }

    /// Under (or over) a strip segment: that section's header, then its content.
    @ViewBuilder func peekColumn(_ section: HubSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch section {
            case .inbox:
                inboxHeader.frame(height: Self.peekLine)
                peekInbox
            case .router:
                peekRouter
            default:
                EmptyView()
            }
        }
        .frame(width: Self.detail - 2 * Self.peekPad, alignment: .leading)
    }

    /// The bar's last cell: a gear. Hovering shows the controls; a click goes to Settings.
    var controlsCell: some View {
        ControlsGear { openApp(.settings) }
    }

    /// The controls: how syncing is going, then the window, the categories and settings, each with its key.
    var peekControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            // As a Claude menu's group label: `px-2 py-1`, footnote, muted.
            syncStatus
                .padding(.horizontal, CDS.Menu.itemPadX)
                .frame(maxWidth: .infinity, minHeight: CDS.Menu.labelHeight, alignment: .leading)
            MenuRow(symbol: "macwindow", title: "Open window", key: store.shortcut(.togglePanel).display) {
                openApp(firstDestination)
            }
            MenuRow(symbol: "tray.2", title: "Inbox categories", key: nil) { openApp(.categories) }
            MenuRow(symbol: "gearshape", title: "Settings", key: "⌘,") { openApp(.settings) }
        }
    }

    /// The inbox list in a panel: scrolls once it's long.
    @ViewBuilder var peekInbox: some View {
        undoLine
        if items.isEmpty {
            emptyInbox
        } else {
            CappedScroll(cap: 360, hub: hub, lazy: AdaptiveStack<EmptyView>.isLazy(items.count)) {
                AdaptiveStack(count: items.count, spacing: 1) { ForEach(items) { itemRow($0).id("i:" + $0.id) } }
                    .motion(Theme.Motion.fade, value: listKey)
            }
        }
    }

    /// The pointer left the bar and its panel: close the panel (a moment later, so going from one to the other,
    /// side by side, doesn't count). Not while the hub still has the pointer: a panel's own hover goes false over a
    /// scroll view inside it (the inbox list), with the pointer still on the panel.
    func hoverChanged() {
        peekLeave?.cancel()
        guard !overBar, !overPanel else { return }
        let hub = hub
        hub.cancelDwell()
        peekLeave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if !Task.isCancelled, !hub.hovering {
                hub.section = nil
                hub.quiet = false
            }
        }
    }
}

/// The gear at the end of the bar, without a tooltip: hovering it opens the controls. Claude's ghost icon button, compact:
/// a 24 square, radius 6, secondary glyph going white on a white-7.5% hover.
struct ControlsGear: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { ControlsGearLabel() }
            .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous),
                                              rest: .clear, hover: CDS.Fill.ghostHover, pressed: CDS.Fill.ghostSelected))
            .accessibilityLabel("Controls")
            .accessibilityHint("Opens Settings; hover for the inbox categories and the window")
    }
}

private struct ControlsGearLabel: View {
    @Environment(\.hoverFillHovering) private var hover

    var body: some View {
        Image(systemName: "gearshape")
            .font(.system(size: CDS.Sidebar.symbol, weight: .medium))
            .foregroundStyle(hover ? Brand.ink : CDS.Text.secondary)
            .frame(width: CDS.Density.compact.control, height: CDS.Density.compact.control)
    }
}

/// A line of the controls' panel, as a Claude menu item (composer-overlays.md §8): 24 tall, 8 at the sides, 6 between a
/// 16pt glyph and its 13pt title, radius 6, white 7.5% under the pointer; the key that does the same as its trailing hint.
struct MenuRow: View {
    let symbol: String
    let title: String
    let key: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CDS.Menu.itemGap) {
                Image(systemName: symbol)
                    .font(.system(size: CDS.Sidebar.symbol, weight: .medium))
                    .foregroundStyle(CDS.Text.secondary)
                    .frame(width: CDS.Density.compact.icon)
                    .accessibilityHidden(true)
                Text(title).font(CDS.sans(CDS.Density.compact.body.0)).foregroundStyle(CDS.Text.primary)
                Spacer(minLength: CDS.Menu.hintGap)
                if let key {
                    Text(key).font(CDS.sans(CDS.Density.compact.footnote.0)).foregroundStyle(CDS.Text.muted)
                }
            }
            .padding(.horizontal, CDS.Menu.itemPadX)
            .frame(height: CDS.Menu.item)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: CDS.Menu.itemRadius, style: .continuous),
                                          rest: .clear, hover: CDS.Fill.ghostHover, pressed: CDS.Fill.ghostSelected))
        .accessibilityLabel(title)
    }
}
