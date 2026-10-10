import SwiftUI

// The app window's sidebar: the bar's items with their names and counts, in Claude's Code-tab sidebar look
// (docs/design/spec/global-sidebar-titlebar.md §2): flat #111, 26pt rows, a 24pt leading slot, 13pt labels.
//
// Inbox: each category shown (its symbol in its colour, what is unread or failing), then Done. The Router after it, with
// what needs you and what is done. Settings and the inbox's categories at the bottom.

struct AppSidebar: View {
    let store: Store
    let navigator: AppNavigator
    typealias M = CDS.Sidebar

    var body: some View {
        let routerCounts = store.routerCounts
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    groupLabel("Inbox")
                    ForEach(store.shownCategories) { category in
                        let badge = store.badge(category)
                        AppSidebarRow(title: category.title, on: navigator.selection == .category(category.id),
                                      action: { navigator.go(.category(category.id)) }) { on in
                            Image(systemName: category.symbol)
                                .font(.system(size: M.symbol, weight: .medium))
                                .foregroundStyle(category.color.swatch.opacity(badge > 0 || on ? 1 : 0.6))
                        } trailing: {
                            if badge > 0 {
                                CountText(badge, color: category.color.swatch)
                            } else if !category.isCI {
                                CountText(store.count(category.id), color: CDS.Text.muted)
                            }
                        }
                        .padding(.bottom, M.sessionGap)
                        .accessibilityValue(badge == 0 ? "Nothing new" : category.isCI ? "\(badge) failing" : "\(badge) unread")
                    }
                    AppSidebarRow(title: "Done", on: navigator.selection == .done, action: { navigator.go(.done) }) { on in
                        Image(systemName: "archivebox")
                            .font(.system(size: M.symbol, weight: .medium))
                            .foregroundStyle(on ? CDS.Text.primary : CDS.Text.muted)
                    } trailing: {
                        CountText(store.doneEntries.count, color: CDS.Text.muted)
                    }
                    .padding(.bottom, M.sessionGap)
                    if store.routerOn {
                        // The Router stands apart from the inbox: a rule and a gap, no header over a single row.
                        Rectangle().fill(CDS.border).frame(height: 0.5).padding(.horizontal, M.labelInset).padding(.top, 4)
                        Color.clear.frame(height: M.groupTop - 4)
                        AppSidebarRow(title: "Router", on: navigator.selection == .router, action: { navigator.go(.router) }) { on in
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: M.symbol, weight: .medium))
                                .foregroundStyle(on ? CDS.Text.primary : CDS.Text.secondary)
                        } trailing: {
                            HStack(spacing: 6) {
                                if routerCounts.needsYou > 0 { CountText(routerCounts.needsYou, color: CDS.Fill.warning) }
                                if routerCounts.done > 0 { CountText(routerCounts.done, color: CDS.Text.accent) }
                            }
                        }
                        .accessibilityValue([routerCounts.needsYou > 0 ? "\(routerCounts.needsYou) need you" : nil,
                                             routerCounts.done > 0 ? "\(routerCounts.done) done" : nil]
                            .compactMap { $0 }.joined(separator: ", ").nonEmpty ?? "Nothing open")
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            VStack(alignment: .leading, spacing: M.sessionGap) {
                AppSidebarRow(title: "Settings", on: navigator.selection == .settings, action: { navigator.go(.settings) }) { on in
                    Image(systemName: "gearshape").font(.system(size: M.symbol, weight: .medium))
                        .foregroundStyle(on ? CDS.Text.primary : CDS.Text.secondary)
                }
                AppSidebarRow(title: "Inbox categories", on: navigator.selection == .categories,
                              action: { navigator.go(.categories) }) { on in
                    Image(systemName: "tray.2").font(.system(size: M.symbol, weight: .medium))
                        .foregroundStyle(on ? CDS.Text.primary : CDS.Text.secondary)
                }
            }
            .padding(.top, 6)
            .overlay(alignment: .top) { Rectangle().fill(CDS.border).frame(height: 0.5) }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .font(CDS.sans(M.rowFont))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// §2.6: a group label, 12/16 muted, its text inset 10.
    private func groupLabel(_ title: String) -> some View {
        Text(title).cdsText((M.groupFont, 16), .regular, CDS.Text.muted)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, M.labelInset)
            .padding(.top, M.groupTop).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct CountText: View {
    let value: Int
    let color: Color
    init(_ value: Int, color: Color) {
        self.value = value
        self.color = color
    }

    var body: some View {
        if value > 0 {
            Text(value > 99 ? "99+" : "\(value)")
                .font(CDS.sans(12, .medium).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }
}

/// `SidebarRowButton` with something at its end: the same 26pt row (radius 6, a 24pt leading slot shifted 4, a 4 gap, 13pt
/// text; white 7.5% on hover, 15% and primary text when picked).
struct AppSidebarRow<Leading: View, Trailing: View>: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @ViewBuilder let leading: (_ on: Bool) -> Leading
    @ViewBuilder let trailing: () -> Trailing
    @State private var hovered = false
    typealias M = CDS.Sidebar

    init(title: String, on: Bool, action: @escaping () -> Void, @ViewBuilder leading: @escaping (_ on: Bool) -> Leading,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.on = on
        self.action = action
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: M.rowGap) {
                leading(on)
                    .frame(width: M.leadingSlot, height: M.leadingSlot)
                    .padding(.leading, M.railShift)
                Text(title)
                    .font(CDS.sans(M.rowFont))
                    .foregroundStyle(on ? CDS.Text.primary : CDS.Text.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                trailing().padding(.trailing, 6)
            }
            .padding(.horizontal, M.rowPadding)
            .frame(height: M.rowHeight)
            .background(RoundedRectangle(cornerRadius: M.radius, style: .continuous)
                .fill(on ? CDS.Fill.ghostSelected : hovered ? CDS.Fill.ghostHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension AppSidebarRow where Trailing == EmptyView {
    init(title: String, on: Bool, action: @escaping () -> Void, @ViewBuilder leading: @escaping (_ on: Bool) -> Leading) {
        self.init(title: title, on: on, action: action, leading: leading) { EmptyView() }
    }
}
