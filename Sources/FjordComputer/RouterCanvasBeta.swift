import SwiftUI

// The canvas is a beta you opt into (Settings › Claude › Canvas view (beta), `RouterModel.canvasBeta`): only then does the
// top bar show List / Canvas, and only once you pick Canvas does Now become one. The list is the Router's own and is drawn
// as it always was; what the canvas needs of its own lives here and in the other RouterCanvas files.

extension RouterModel {
    /// The beta turned on and Canvas picked, as you would in Settings then the top bar (shots and tests).
    func pickCanvas() {
        canvasBeta = true
        layout = .canvas
    }
}

/// Now's side on the canvas: the same bar as the list's (the pane switch in a narrow window, then the canvas's chips and
/// buttons, the Router's status line on 26) over the canvas, which places what Now's scroll holds over itself.
struct CanvasNowColumn: View {
    let store: Store
    let model: RouterModel
    let bar: Bool
    @Environment(\.routerGutter) private var gutter

    var body: some View {
        let page = model.zones(store)
        if #available(macOS 26, *) {
            RouterCanvas(store: store, model: model, page: page, narrow: bar)
                .safeAreaBar(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        chips(page)
                        RouterBusyLine(store: store)
                    }
                    .background(CDS.Surface.s1)
                }
        } else {
            VStack(spacing: 0) {
                chips(page)
                RouterCanvas(store: store, model: model, page: page, narrow: bar)
            }
        }
    }

    /// The canvas's chips filter it, with its own buttons at the column's end (RouterCanvas.swift).
    private func chips(_ page: RouterPage) -> some View {
        HStack(spacing: 12) {
            if bar { PaneSwitch(store: store, model: model) }
            CanvasBar(store: store, model: model, page: page, compact: bar, gutter: gutter)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

/// List or Canvas, in the top bar while the beta is on: how Now is drawn. The pane switch's pill (`PaneSwitch`), its two
/// segments icons named in their tips, Canvas's tip saying it is a beta, and a Beta tag beside the pill.
struct RouterLayoutSwitch: View {
    let model: RouterModel
    @State private var hovered: RouterLayout?

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                segment(.list, "List", icon: "list.bullet", help: "Now as sections, one under the other")
                segment(.canvas, "Canvas", icon: "square.on.square.dashed",
                        help: "Beta: each project a frame, its sessions grouped; pan, pinch, double-click to fit")
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
