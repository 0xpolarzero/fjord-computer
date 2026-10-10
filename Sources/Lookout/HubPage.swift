import SwiftUI

// Settings and the inbox's categories: a page that takes the rows' place while the bar stays.

extension LookoutHub {
    // MARK: Pages

    var page: some View {
        VStack(spacing: 0) {
            pageHeader
            IslandRule()
            Group {
                if hub.page == .categories { CategoriesView(store: store, hub: hub) } else { SettingsView(store: store, hub: hub) }
            }
            .id(hub.page)
            .transition(reduce ? .opacity.animation(Theme.Motion.fade) : .push(from: hub.forward ? .trailing : .leading))
            .frame(maxHeight: .infinity, alignment: .top)
            // Cut short by the hub's height: the last line fades into the bottom padding instead of hitting the edge.
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 12)
                }
            }
        }
    }

    /// The one way back, and the switch between the two pages (which doubles as their title).
    var pageHeader: some View {
        HStack(spacing: Theme.Space.sm) {
            IconButton(symbol: "chevron.left", help: "Back", detail: "Esc", size: IconButton.Size.header) { hub.back() }
            // The switch is the title: it says which page is open.
            pageSwitch
            Spacer(minLength: 0)
        }
        .padding(.leading, Self.inset + 4)
        .padding(.trailing, Self.inset + 2)
        // Claude's sidebar title row: chrome buttons and the switch on one 40pt line.
        .frame(height: 40)
    }

    /// "Settings | Inbox", the open one picked: Claude's compact SegmentedControl (a white-5% track, the picked
    /// segment on a white-10% thumb with its 1pt ring).
    var pageSwitch: some View {
        HStack(spacing: 0) {
            ForEach([HubPage.settings, .categories], id: \.self) { p in
                PageSegment(label: p == .settings ? "Settings" : "Inbox", selected: hub.page == p) { hub.go(p) }
            }
        }
        .padding(1)
        .frame(height: CDS.Segmented.height)
        .background(RoundedRectangle(cornerRadius: CDS.Segmented.radius, style: .continuous).fill(CDS.Segmented.track))
    }
}

/// One segment of the pages' switch: muted, primary on hover and once picked (on the thumb).
private struct PageSegment: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let thumb = RoundedRectangle(cornerRadius: CDS.Segmented.radius - 1, style: .continuous)
        Button(action: action) {
            Text(label)
                .font(CDS.sans(CDS.Density.compact.body.0))
                .foregroundStyle(selected || hover ? CDS.Text.primary : CDS.Text.muted)
                .padding(.horizontal, CDS.Segmented.padX)
                .frame(maxHeight: .infinity)
                .background {
                    if selected {
                        thumb.fill(CDS.Segmented.thumb)
                            .overlay(thumb.strokeBorder(CDS.border, lineWidth: 1))
                            .shadow(color: CDS.fieldShadow, radius: 1, y: 1)
                    }
                }
                .contentShape(thumb)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
