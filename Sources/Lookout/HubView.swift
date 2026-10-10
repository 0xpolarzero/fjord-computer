import AppKit
import SwiftUI

// Lookout docked: one bar on a screen edge. Hovering an item opens its peek beside the bar, and the peek's rows act; a click
// opens the app window (AppWindow.swift) on that item, and the bar leaves the edge until the window closes.

/// A tab of the inbox: a category, or Done at the end.
enum InboxTab: Hashable {
    case category(UUID)
    case done
}

extension EnvironmentValues {
    /// Opens the app window on a place. The window controller in the app; a toast in shots.
    @Entry var openApp: (AppDestination) -> Void = { _ in }
    /// Opens the app window on Settings, scrolled to Updates.
    @Entry var openUpdates: () -> Void = {}
    /// Opens the app window on the Router, on a card if one is given.
    @Entry var openRouter: (String?) -> Void = { _ in }
    /// Opens the app window on the Router, scrolled to a message of its conversation (an inbox action's).
    @Entry var openRouterMessage: (UUID) -> Void = { _ in }
    /// Picks a card in the Router (window open or not), after a click on it elsewhere opened its session.
    @Entry var pickRouterCard: (String) -> Void = { _ in }
}

@Observable
@MainActor
final class HubState {
    var hovering = false
    /// No hover panels until the pointer has left the bar (set when the bar comes back under a still pointer).
    var quiet = false
    /// The bar is away while the app window is open (the playground draws it, the app orders its panel out).
    var barHidden = false
    /// "i:<item id>": the row the pointer is on (or the one an opened notification names); its actions show.
    var selection: String?
    /// The last row asked for (a notification's): the lists scroll to it. Never set by hovering, so the pointer moving over a
    /// row doesn't move the list.
    var keyboardSelection: ScrollRequest?
    /// The tab the inbox peek shows: the category cell the pointer is on, or one of its tabs; nil is the first category shown.
    var tab: InboxTab? {
        didSet { selection = nil; keyboardSelection = nil }
    }
    /// Asks the lists to scroll to a row, even one asked for before (a new request every time).
    func requestScroll(_ id: String) {
        keyboardSelection = ScrollRequest(id: id, seq: (keyboardSelection?.seq ?? 0) + 1)
    }
    /// Asks Settings to scroll to a section (by name), once it is open: where Check for Updates shows what it found.
    var settingsScroll: ScrollRequest?
    /// Asks Settings to scroll to its Updates section, also when it is open already, scrolled elsewhere.
    func showUpdates() {
        settingsScroll = ScrollRequest(id: SettingsView.updatesID, seq: (settingsScroll?.seq ?? 0) + 1)
    }
    /// Asks the categories page to open a category's editor, or unfold a group (a Router change's Open button): it takes the
    /// request when it appears, or at once when it is open.
    var categoryRequest: ScrollRequest?
    var groupRequest: ScrollRequest?
    func openCategory(_ id: UUID) { categoryRequest = ScrollRequest(id: id.uuidString, seq: (categoryRequest?.seq ?? 0) + 1) }
    func openGroup(_ id: UUID) { groupRequest = ScrollRequest(id: id.uuidString, seq: (groupRequest?.seq ?? 0) + 1) }
    var toast: String?

    /// The category editor's own step back, set while one is open (see `CategoriesView`).
    @ObservationIgnored var stepBack: (() -> Bool)?

    /// The section the pointer is on: just that one opens beside the bar.
    var section: HubSection?
    /// The bar is being carried to another edge: no panels meanwhile.
    @ObservationIgnored var dragging = false
    @ObservationIgnored private var dwell: Task<Void, Never>?

    /// The pointer entered a section. The first panel waits for the pointer to settle (so sweeping along the edge
    /// opens nothing); once one is open, moving to another section switches at once, with no transition.
    func enter(_ next: HubSection) {
        dwell?.cancel()
        guard !dragging else { return }
        if section != nil {
            guard section != next else { return }
            var instant = Transaction(animation: nil)
            instant.disablesAnimations = true
            withTransaction(instant) { section = next }
            return
        }
        dwell = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            if !Task.isCancelled, self?.dragging == false { self?.section = next }
        }
    }

    /// The pointer left a section before it settled: nothing opens.
    func cancelDwell() { dwell?.cancel() }

    /// Where that section's panel is (in the hub's window), so the window takes the mouse there too.
    @ObservationIgnored var panelFrame: CGRect = .zero
    /// The panel's frame while one is showing. Not cleared when a panel goes: one closing (still fading out) as the
    /// next opens would clear the new one's frame, leaving the window deaf to the pointer over most of it.
    var openPanelFrame: CGRect? {
        section != nil && !quiet && panelFrame != .zero ? panelFrame : nil
    }
}

/// The bar, and beside it the peek of the section the pointer is on: each cell of the bar stays beside the content it stands for.
struct LookoutHub: View {
    let store: Store
    let ui: UIState
    @Bindable var hub: HubState
    /// Where each section's cells are in the bar, and whether the pointer is on the bar or a section's panel.
    @State var sectionFrames: [HubSection: CGRect] = [:]
    @State var overBar = false
    @State var overPanel = false
    @State var peekLeave: Task<Void, Never>?
    /// The bar's size and the open panel's natural size, to place the panel against the bar's ends.
    @State var barSize: CGSize = .zero
    @State var peekSizes: [HubSection: CGSize] = [:]
    @Environment(\.accessibilityReduceMotion) var reduce
    /// Opens the app window on a place, or on a Router card.
    @Environment(\.openApp) var openApp
    @Environment(\.openUpdates) var openUpdates
    @Environment(\.openRouter) var openRouter
    @Environment(\.pickRouterCard) var pickRouterCard

    /// The bar's depth: a cell's width on the sides, the strip's height along the top and bottom.
    static let cell = Theme.Metrics.bar
    /// A peek's width.
    static let detail: CGFloat = 400
    /// The one outer inset. Pieces pad their own 8 inside it, so text starts 14pt from the hub's side everywhere.
    static let inset = Theme.Metrics.inset
    /// The hub's one coordinate space name (the hosting root's).
    static let rootSpace = "hub-root"

    var edge: DockEdge { ui.edge }

    var body: some View {
        let shape = barOutline
        Group {
            if edge.isHorizontal { horizontal } else { vertical }
        }
        .coordinateSpace(.named(Self.barSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in if barSize != size { barSize = size } }
        .onHover { overBar = $0; hoverChanged() }
        .background(shape.fill(Theme.bg))
        // Claude's panel ring (`shadow-panel`'s inset white 10%) against the desktop.
        .overlay(shape.strokeBorder(CDS.border, lineWidth: 1))
        .clipShape(shape)
        // The hovered section's panel, outside the bar's clip; the bar's own size doesn't change.
        .overlay(alignment: peekAlignment) { peekPanel }
        // Shadows come from shapes alone, in a layer under the bar and its panel (never a blurred composite of their
        // content, which would be redone on every frame of anything animating inside): the panel's can't fall
        // across the bar, which is opaque above it.
        .background(alignment: peekAlignment) { peekShadow }
        .background {
            // Claude's `shadow-panel` (its two drops) while a panel is open; at rest, only its near one, so the bar sits light.
            let open = peeking != nil
            shape.fill(Theme.bg)
                .shadow(color: open ? CDS.PanelShadow.far.color : .clear, radius: CDS.PanelShadow.far.radius,
                        y: CDS.PanelShadow.far.y)
                .shadow(color: CDS.PanelShadow.near.color, radius: CDS.PanelShadow.near.radius, y: CDS.PanelShadow.near.y)
        }
        .motion(Theme.Motion.fade, value: peeking != nil)
        .fixedSize()
        .contextMenu {
            Button("Open Lookout") { openApp(firstDestination) }
            if store.routerOn {
                Button("Open Router") { openApp(.router) }
            }
            Button("Settings…") { openApp(.settings) }
            Button("Inbox Categories…") { openApp(.categories) }
            if store.updater.isRelease {
                // Settings' update row says what the check finds (up to date, or why it failed); the bar has no room to.
                Button("Check for Updates") {
                    openUpdates()
                    Task { await store.updater.update(manual: true) }
                }
            }
            Divider()
            Button("Quit Lookout") { NSApp.terminate(nil) }
        }
        .modifier(Brand.Scheme())
        .background(UpdateAnnouncer(updater: store.updater))
    }

    /// Where the GitHub mark leads: the first category with something unread, else the first.
    var firstDestination: AppDestination { AppDestination(store.tabNeedingYou) }

    // MARK: Data

    /// What the inbox peek lists.
    var items: [InboxEntry] { store.entries(in: store.hubTab(hub)) }
    /// What the inbox list animates on: its entries changing, or the tab swapping them.
    struct ListKey: Equatable { let revision: Int; let tab: InboxTab }
    var listKey: ListKey { ListKey(revision: store.inboxRevision, tab: store.hubTab(hub)) }

    // MARK: Vertical (left / right edges)

    var vertical: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) { mainRows }
            // Last, the gear: hover for the controls, a click for Settings.
            sectionDivider
            controlsCell.padding(.vertical, 9)
                .frame(width: Self.cell)
                .modifier(probe(.controls))
        }
    }

    @ViewBuilder var mainRows: some View {
        // Inbox: each section's well, its icon and its categories' cells under it, apart from the Router. With nothing shown,
        // the GitHub mark alone.
        let sections = store.barSections
        VStack(spacing: 6) {
            if sections.isEmpty { inboxIcon.padding(.vertical, 2).frame(width: Self.cell) }
            ForEach(Array(sections.enumerated()), id: \.element.id) { i, part in
                VStack(spacing: 0) {
                    if let section = part.section {
                        sectionCell(section, part).padding(.vertical, 2).frame(width: Self.cell)
                    }
                    if part.section?.isCollapsed != true {
                        VStack(spacing: 0) { categoryCells(part.categories) }.frame(width: Self.cell)
                    }
                }
                .padding(.bottom, 2)
                .frame(width: Self.cell)
                .background {
                    if part.section != nil { sectionWell(first: i == 0).fill(CDS.alpha(0.06)).padding(.horizontal, 6) }
                }
            }
        }
        // Down from the bar's top as far as a well is in from its sides, so the first sits inset all round.
        .padding(.top, 6)
        .frame(width: Self.cell)
        .modifier(probe(.inbox))
        // The Router: its cell and counts.
        if store.routerOn {
            sectionDivider.padding(.vertical, 6)
            routerCell.frame(width: Self.cell)
                .modifier(probe(.router))
        }
        if store.updater.showsInPill {
            UpdateButton(updater: store.updater, horizontal: false).padding(.vertical, 4)
                .frame(width: Self.cell)
                .transition(.scaleFade(0.8, reduce: reduce))
        }
    }

    /// A section's well, 6pt inside the bar's sides. The first's top corners follow the bar's (concentric where the bar is
    /// rounded, the tile's radius where it meets the screen edge); every other corner is the tile's.
    func sectionWell(first: Bool) -> UnevenRoundedRectangle {
        let base = CDS.Tile.radius + 4, bar = barOutline.cornerRadii
        func inner(_ r: CGFloat) -> CGFloat { first ? max(base, r - 6) : base }
        return UnevenRoundedRectangle(topLeadingRadius: inner(bar.topLeading), bottomLeadingRadius: base,
                                      bottomTrailingRadius: base, topTrailingRadius: inner(bar.topTrailing), style: .continuous)
    }

    /// A short rule centred in the bar.
    var sectionDivider: some View {
        IslandRule()
            .frame(width: Self.cell - 24)
            .frame(width: Self.cell)
            .padding(.vertical, 4)
    }

    // MARK: Horizontal (top / bottom edges)

    var horizontal: some View {
        HStack(alignment: .center, spacing: 0) { strip }
            .frame(height: Self.cell)
    }

    /// The bar along the top or bottom: the inbox's segment, the Router's, the gear, the update button.
    @ViewBuilder var strip: some View {
        let sections = store.barSections
        HStack(spacing: 12) {
            if sections.isEmpty { inboxIcon }
            ForEach(sections) { part in
                HStack(spacing: 0) {
                    if let section = part.section { sectionCell(section, part) }
                    // The categories' cells beside its icon.
                    if part.section?.isCollapsed != true { HStack(spacing: 0) { categoryCells(part.categories) } }
                }
                .background {
                    if part.section != nil {
                        RoundedRectangle(cornerRadius: CDS.Tile.radius + 4, style: .continuous).fill(CDS.alpha(0.06))
                            .padding(.vertical, 5).padding(.horizontal, -3)
                    }
                }
            }
        }
        .padding(.leading, Self.inset + 1)
        .padding(.trailing, Self.inset)
        .frame(maxHeight: .infinity)
        .modifier(probe(.inbox))
        if store.routerOn {
            stripDivider.padding(.horizontal, 6)
            routerCell
                .padding(.leading, Self.inset + 1)
                .padding(.trailing, Self.inset)
                .frame(maxHeight: .infinity)
                // The whole segment opens the window, not only its cell.
                .contentShape(Rectangle())
                .onTapGesture { openApp(.router) }
                .modifier(probe(.router))
        }
        stripDivider
        controlsCell
            .padding(.horizontal, Self.inset)
            .frame(maxHeight: .infinity)
            .modifier(probe(.controls))
        if store.updater.showsInPill {
            stripDivider
            HStack(spacing: 0) {
                UpdateButton(updater: store.updater, horizontal: true)
                UpdateMenu(updater: store.updater)
            }
            .padding(.horizontal, 6)
        }
    }

    var stripDivider: some View {
        IslandRule(axis: .vertical).frame(height: 16)
    }
}

/// Under the Router's header: Claude's session files missing or unreadable (nothing when all is well).
struct ClaudeNotice: View {
    let store: Store

    var body: some View {
        switch store.claudeLink {
        case .missing, .unreadable:
            HStack(spacing: 6) { ClaudeLinkStatus(store: store) }
                // One element for VoiceOver: what is wrong, said as shown.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(store.claudeLink == .missing ? "Claude's sessions not found" : "Can't read Claude's sessions")
                .font(Theme.Typography.meta)
                .foregroundStyle(Theme.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Theme.Space.xs)
        default:
            EmptyView()
        }
    }
}

/// Beside the sync status, on every edge: the GitHub rate limit running low (nothing otherwise).
struct RateNotice: View {
    let store: Store
    /// Takes the whole line (its text at the leading edge); off, only the room it needs.
    var fill = true

    var body: some View {
        RateLimitWarning(store: store)
            .font(Theme.Typography.meta)
            .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
    }
}

// MARK: Island pieces (Claude's frame: dividers, group labels)

/// Claude's divider: `--cds-border` (white 10%) at 0.5pt. `inset` trims both ends.
struct IslandRule: View {
    var axis: Axis = .horizontal
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(CDS.border)
            .frame(width: axis == .vertical ? CDS.hairline : nil, height: axis == .horizontal ? CDS.hairline : nil)
            .padding(axis == .horizontal ? .horizontal : .vertical, inset)
    }
}
