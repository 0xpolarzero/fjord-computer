import SwiftUI

// The app window's sidebar: the bar's items with their names and counts, in Claude's Code-tab sidebar look
// (docs/design/spec/global-sidebar-titlebar.md §2): flat #111, 26pt rows, a 24pt leading slot, 13pt labels.
//
// Inbox: each category shown (its symbol in its colour, what is unread or failing), then Done. The Router after it, with
// what needs you and what is done. Settings and the inbox's categories at the bottom.

/// Whether the sidebar is an icon rail, remembered across launches (a shot or a test passes `defaults: nil`).
@MainActor @Observable
final class SidebarState {
    static let shared = SidebarState(defaults: .standard)
    private static let key = "appSidebarCollapsed"

    @ObservationIgnored private let defaults: UserDefaults?
    private(set) var collapsed: Bool

    init(defaults: UserDefaults?, collapsed: Bool? = nil) {
        self.defaults = defaults
        self.collapsed = collapsed ?? defaults?.bool(forKey: Self.key) ?? false
    }

    /// One spring on the width (and on everything that follows it); under Reduce Motion a short fade, no travel.
    static var animation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.35, bounce: 0.15)
    }

    func set(collapsed value: Bool) {
        guard value != collapsed else { return }
        withAnimation(Self.animation) { collapsed = value }
        defaults?.set(value, forKey: Self.key)
    }

    func toggle() { set(collapsed: !collapsed) }
}

/// View ▸ Collapse Sidebar, ⌃⌘S.
@MainActor
final class SidebarMenu: NSObject, NSMenuItemValidation {
    static let shared = SidebarMenu()
    private let item = NSMenuItem(title: "Collapse Sidebar", action: #selector(toggle), keyEquivalent: "s")

    func makeItem() -> NSMenuItem {
        let top = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "View")
        item.target = self
        item.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(item)
        top.submenu = menu
        return top
    }

    @objc private func toggle() { SidebarState.shared.toggle() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.title = SidebarState.shared.collapsed ? "Expand Sidebar" : "Collapse Sidebar"
        return AppWindowController.active?.isOpen == true
    }
}

extension EnvironmentValues {
    @Entry var sidebarCollapsed = false
}

/// A count on the corner of a rail icon (the bar's badge).
struct RailBadge {
    let count: Int
    let fill: Color
    let ink: Color
}

struct AppSidebar: View {
    let store: Store
    let navigator: AppNavigator
    let collapsed: Bool
    typealias M = CDS.Sidebar
    /// The rail: the bar's 28pt tile centred in 52 (the expanded rows' icons sit at the same centre, so they never move).
    static let railWidth: CGFloat = 52
    static let tile: CGFloat = CDS.Tile.size

    var body: some View {
        let routerCounts = store.routerCounts
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    groupLabel("Inbox")
                    ForEach(store.shownCategories) { category in
                        let badge = store.badge(category)
                        AppSidebarRow(title: category.title, on: navigator.selection == .category(category.id),
                                      badge: badge > 0 ? RailBadge(count: badge, fill: category.color.swatch, ink: category.color.ink) : nil,
                                      tip: badge == 0 ? category.title : "\(category.title) · \(category.isCI ? "\(badge) failing" : "\(badge) new")",
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
                        .padding(.bottom, rowGap)
                        .accessibilityValue(badge == 0 ? "Nothing new" : category.isCI ? "\(badge) failing" : "\(badge) unread")
                    }
                    AppSidebarRow(title: "Done", on: navigator.selection == .done,
                                  tip: "Done · \(store.doneEntries.count)", action: { navigator.go(.done) }) { on in
                        Image(systemName: "archivebox")
                            .font(.system(size: M.symbol, weight: .medium))
                            .foregroundStyle(on ? CDS.Text.primary : CDS.Text.muted)
                    } trailing: {
                        CountText(store.doneEntries.count, color: CDS.Text.muted)
                    }
                    .padding(.bottom, rowGap)
                    if store.routerOn {
                        // The Router stands apart from the inbox: a rule and a gap, no header over a single row.
                        rule.padding(.top, 4)
                        Color.clear.frame(height: M.groupTop - 4)
                        AppSidebarRow(title: "Router", on: navigator.selection == .router,
                                      badge: routerCounts.needsYou + routerCounts.done > 0
                                          ? RailBadge(count: routerCounts.needsYou + routerCounts.done,
                                                      fill: routerCounts.needsYou > 0 ? CDS.Fill.warning : CDS.Fill.accent,
                                                      ink: routerCounts.needsYou > 0 ? CDS.Text.onPrimary : .white)
                                          : nil,
                                      tip: Self.routerTip(routerCounts),
                                      action: { navigator.go(.router) }) { on in
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
            VStack(alignment: .leading, spacing: rowGap) {
                AppSidebarRow(title: "Settings", on: navigator.selection == .settings, tip: "Settings", action: { navigator.go(.settings) }) { on in
                    Image(systemName: "gearshape").font(.system(size: M.symbol, weight: .medium))
                        .foregroundStyle(on ? CDS.Text.primary : CDS.Text.secondary)
                }
                AppSidebarRow(title: "Inbox categories", on: navigator.selection == .categories, tip: "Inbox categories",
                              action: { navigator.go(.categories) }) { on in
                    Image(systemName: "tray.2").font(.system(size: M.symbol, weight: .medium))
                        .foregroundStyle(on ? CDS.Text.primary : CDS.Text.secondary)
                }
            }
            .padding(.top, 6)
            .overlay(alignment: .top) {
                Rectangle().fill(CDS.border).frame(height: 0.5)
                    .frame(width: collapsed ? Self.tile : AppRootView.sidebarWidth - 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, collapsed ? 4 : 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .font(CDS.sans(M.rowFont))
        .environment(\.sidebarCollapsed, collapsed)
        // Always laid out at its full width: the frame around it narrows, so nothing here reflows or moves.
        .frame(width: AppRootView.sidebarWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    /// Tiles sit a little further apart than rows (28 against 26).
    private var rowGap: CGFloat { collapsed ? 4 : M.sessionGap }

    /// The rule between groups: the rows' width, or the tile's in the rail.
    private var rule: some View {
        Rectangle().fill(CDS.border).frame(height: 0.5)
            .frame(width: collapsed ? Self.tile : AppRootView.sidebarWidth - 16 - 2 * M.labelInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, collapsed ? 4 : M.labelInset)
    }

    private static func routerTip(_ c: (needsYou: Int, done: Int)) -> String {
        let parts = [c.needsYou > 0 ? "\(c.needsYou) need you" : nil, c.done > 0 ? "\(c.done) done" : nil].compactMap { $0 }
        return parts.isEmpty ? "Router" : "Router · " + parts.joined(separator: ", ")
    }

    /// §2.6: a group label, 12/16 muted, its text inset 10.
    private func groupLabel(_ title: String) -> some View {
        Text(title).cdsText((M.groupFont, 16), .regular, CDS.Text.muted)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, M.labelInset)
            .padding(.top, M.groupTop).padding(.bottom, 4)
            .sidebarText(collapsed)
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
    let badge: RailBadge?
    let tip: String
    let action: () -> Void
    @ViewBuilder let leading: (_ on: Bool) -> Leading
    @ViewBuilder let trailing: () -> Trailing
    @State private var hovered = false
    @Environment(\.sidebarCollapsed) private var collapsed
    typealias M = CDS.Sidebar

    init(title: String, on: Bool, badge: RailBadge? = nil, tip: String? = nil, action: @escaping () -> Void,
         @ViewBuilder leading: @escaping (_ on: Bool) -> Leading, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.on = on
        self.badge = badge
        self.tip = tip ?? title
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
                    .overlay(alignment: .topTrailing) {
                        // The bar's corner count, on the rail only; it comes in after the labels have gone.
                        if let badge {
                            CornerBadge(count: badge.count, fill: badge.fill, ink: badge.ink)
                                .offset(x: 2, y: -2)
                                .opacity(collapsed ? 1 : 0)
                                .animation(collapsed ? .easeIn(duration: 0.18).delay(0.12) : .easeOut(duration: 0.08), value: collapsed)
                        }
                    }
                Group {
                    Text(title)
                        .font(CDS.sans(M.rowFont))
                        .foregroundStyle(on ? CDS.Text.primary : CDS.Text.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    trailing().padding(.trailing, 6)
                }
                .sidebarText(collapsed)
            }
            .padding(.horizontal, M.rowPadding)
            .frame(height: M.rowHeight)
            // The full row, or the bar's tile in the rail: one shape whose width follows the sidebar's.
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: M.radius, style: .continuous)
                    .fill(on ? CDS.Fill.ghostSelected : hovered ? CDS.Fill.ghostHover : .clear)
                    .frame(width: collapsed ? AppSidebar.tile : AppRootView.sidebarWidth - 16,
                           height: collapsed ? AppSidebar.tile : M.rowHeight)
                    .padding(.leading, collapsed ? 4 : 0)
            }
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                if collapsed {
                    Rectangle().fill(.clear).frame(width: AppSidebar.tile, height: AppSidebar.tile).contentShape(Rectangle())
                        .padding(.leading, 4).tip(tip)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension AppSidebarRow where Trailing == EmptyView {
    init(title: String, on: Bool, badge: RailBadge? = nil, tip: String? = nil, action: @escaping () -> Void,
         @ViewBuilder leading: @escaping (_ on: Bool) -> Leading) {
        self.init(title: title, on: on, badge: badge, tip: tip, action: action, leading: leading) { EmptyView() }
    }
}

private struct SidebarTextModifier: ViewModifier {
    let collapsed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// Out early on collapse (before the width has gone far), in late on expand (once there is room), sliding a few points
    /// toward the icons while it goes; Reduce Motion only fades, briefly.
    func body(content: Content) -> some View {
        content
            .opacity(collapsed ? 0 : 1)
            .offset(x: collapsed && !reduce ? -8 : 0)
            .animation(reduce ? .easeOut(duration: 0.1)
                       : collapsed ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22).delay(0.14), value: collapsed)
            .allowsHitTesting(!collapsed)
    }
}

private extension View {
    func sidebarText(_ collapsed: Bool) -> some View { modifier(SidebarTextModifier(collapsed: collapsed)) }
}
