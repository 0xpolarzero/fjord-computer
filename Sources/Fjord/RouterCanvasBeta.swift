import SwiftUI

// The canvas is a beta you try from the Router's top bar (List / Canvas, tagged Beta); Now is the list until you pick
// Canvas. The list is the Router's own and is drawn as it always was; what the canvas needs of its own lives here and in
// the other RouterCanvas files.

extension RouterModel {
    /// Canvas picked, as the top bar's switch does (shots and tests).
    func pickCanvas() {
        layout = .canvas
    }

    /// Lanes picked (shots).
    func pickLanes() {
        layout = .lanes
    }
}

/// The Router's page as a canvas: the canvas over all of it under the top bar, its chips (and what Now's list says over
/// its sections) floating at its top left, its buttons at its top right, and the history a panel that slides in over its
/// right side from the History button, Esc or the button closing it. The history is kept while hidden (off the page), so
/// it opens where you left it.
struct CanvasPage: View {
    let store: Store
    let model: RouterModel

    /// The panel's width at most, and the room over it for the buttons.
    static let panelWidth: CGFloat = 480
    static let panelTop: CGFloat = 52
    static let inset: CGFloat = 12

    var body: some View {
        let page = model.zones(store)
        GeometryReader { geometry in
            let size = geometry.size
            let open = model.pane == .history
            let width = min(Self.panelWidth, max(320, size.width * 0.45))
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            ZStack(alignment: .topLeading) {
                RouterCanvas(store: store, model: model, page: page)
                VStack(alignment: .leading, spacing: 8) {
                    CanvasChips(store: store, model: model, page: page)
                    CanvasNotices(store: store, model: model, page: page)
                }
                .padding(.leading, CanvasMetrics.pad)
                .padding(.top, Self.inset)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if model.canvas.topRoom != height { model.canvas.topRoom = height }
                }
                .frame(width: max(0, size.width - 300), alignment: .leading)
                CanvasControls(store: store, model: model, page: page)
                    .padding(.trailing, CanvasMetrics.pad)
                    .padding(.top, Self.inset)
                    .frame(width: size.width, alignment: .trailing)
                HistoryColumn(store: store, model: model, bar: false, hidden: !open)
                    .column(width)
                    .frame(width: width, height: max(0, size.height - Self.panelTop - Self.inset))
                    .background(CDS.Surface.s1)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(CDS.border, lineWidth: 1))
                    .shadow(color: CDS.PanelShadow.near.color.opacity(0.6), radius: CDS.PanelShadow.near.radius, y: CDS.PanelShadow.near.y)
                    .shadow(color: CDS.PanelShadow.far.color.opacity(0.6), radius: CDS.PanelShadow.far.radius, y: CDS.PanelShadow.far.y)
                    .offset(x: open ? size.width - width - CanvasMetrics.pad : size.width + 32, y: Self.panelTop)
                    .opacity(open ? 1 : 0)
                    .motion(.spatial, value: open)
                    .allowsHitTesting(open)
                    .accessibilityHidden(!open)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("History")
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }
}

/// List or Canvas, in the top bar: how Now is drawn. The pane switch's pill (`PaneSwitch`), its two
/// segments icons named in their tips, Canvas's tip saying it is a beta, and a Beta tag beside the pill.
struct RouterLayoutSwitch: View {
    let model: RouterModel
    @State private var hovered: RouterLayout?

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                segment(.list, "List", icon: "list.bullet", help: "Now as sections, one under the other")
                segment(.canvas, "Canvas", icon: "square.on.square.dashed",
                        help: "Beta: each project a frame on an infinite canvas; pan, pinch, drag a frame to move it, double-click to fit")
                segment(.lanes, "Lanes", icon: "rectangle.split.3x1",
                        help: "Prototype: a project to a row, a state to a column; what needs you numbered in visit order")
            }
            .padding(1)
            .frame(height: ZoneChip.height)
            .background(Capsule(style: .continuous).fill(CDS.Segmented.track).background(Capsule(style: .continuous).fill(CDS.Surface.s1)))
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Show Now as")
            BetaTag()
        }
    }

    private func segment(_ layout: RouterLayout, _ title: String, icon: String, help: String) -> some View {
        let picked = model.layout == layout
        let thumb = ZoneChip.height - 2
        let ink = picked || hovered == layout ? CDS.Text.primary : CDS.Text.muted
        return Button { model.layout = layout } label: {
            Image(systemName: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(ink)
                .frame(width: 14).frame(maxHeight: .infinity)
                .padding(.horizontal, 6)
                .background {
                    if picked {
                        Capsule(style: .continuous).fill(CDS.Segmented.thumb)
                            .overlay(Capsule(style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
                            .bakedShadow(CDS.fieldShadow, .rounded(thumb / 2), radius: 1, y: 1, fill: CDS.Segmented.thumb)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? layout : (hovered == layout ? nil : hovered) }
        .accessibilityLabel(layout == .canvas ? "Canvas, beta" : title)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .tip(title, help)
    }
}

/// "Beta", as the app's tags are (Claude's Badge, xs) in the accent's tint.
struct BetaTag: View {
    var body: some View {
        Text("Beta")
            .font(CDS.sans(CDS.Badge.font, .medium))
            .foregroundStyle(CDS.BadgeTint.accentText)
            .padding(.horizontal, CDS.Badge.padX)
            .frame(height: CDS.Badge.height)
            .background(RoundedRectangle(cornerRadius: CDS.Badge.radius, style: .continuous).fill(CDS.BadgeTint.accentFill))
            .fixedSize()
            .accessibilityHidden(true)
    }
}
