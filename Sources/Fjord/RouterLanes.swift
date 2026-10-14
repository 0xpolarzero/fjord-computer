import SwiftUI

// Lanes (a prototype): Now as a grid, a project to a row and a state to a column. Read down the first column, it is what
// needs you across every project; read along a row, it is one project's whole picture. Rows come in the canvas's order
// (what needs you first), and a project with nothing for you shrinks to a line. The cards that need you are numbered in
// visit order: a project's all, then the next project's, so you switch projects once per project, not once per card.

/// The columns' widths for a page this wide: the project's column and the two side ones narrow first, down to a floor,
/// and Needs you takes what's left, up to a cap.
struct LaneWidths {
    var gutter: CGFloat
    var side: CGFloat
    var needs: CGFloat

    init(width: CGFloat) {
        let room = width - 2 * LaneMetrics.rowPad - 3 * LaneMetrics.gap - VisitBadge.size - 8
        gutter = min(220, max(150, room * 0.17))
        side = min(270, max(200, room * 0.2))
        needs = min(LaneMetrics.needsMax, max(300, room - gutter - 2 * side))
    }
}

/// The grid's measures.
enum LaneMetrics {
    static let gap: CGFloat = 16
    static let rowPad: CGFloat = 14
    static let needsMax: CGFloat = 640
    /// The room under the grid for the composer floating over it.
    static let bottom: CGFloat = 150
}

/// A lane's columns: Needs you, Worth a look, and what runs on its own (Waiting and Working together).
enum LaneColumn: CaseIterable, Identifiable {
    case needs, notes, running

    var id: Self { self }
    var title: String {
        switch self {
        case .needs: "Needs you"
        case .notes: "Worth a look"
        case .running: "Running"
        }
    }
    var symbol: String {
        switch self {
        case .needs: RouterZone.needs.symbol
        case .notes: RouterZone.notes.symbol
        case .running: RouterZone.working.symbol
        }
    }
    var tint: Color {
        switch self {
        case .needs: RouterZone.needs.tint
        case .notes: RouterZone.notes.tint
        case .running: CDS.Text.muted
        }
    }
    var groups: [CanvasGroup] {
        switch self {
        case .needs: [.needs]
        case .notes: [.notes]
        case .running: [.waiting, .working]
        }
    }
}

extension CanvasFolder {
    func items(_ column: LaneColumn) -> [CanvasItem] {
        column.groups.flatMap { g in groups.first { $0.group == g }?.items ?? [] }
    }
    var doneCount: Int { groups.first { $0.group == .done }.map { $0.items.count + $0.more } ?? 0 }
    /// Nothing for you in it: a line, its running sessions beside its name.
    var quiet: Bool { items(.needs).isEmpty && items(.notes).isEmpty }
}

struct LanesPage: View {
    let store: Store
    let model: RouterModel

    var body: some View {
        let page = model.zones(store)
        let folders = model.canvasFolders(store, page: page).filter { !$0.doneOnly }
        // Visit order: row by row, each project's cards together.
        let visits = Dictionary(uniqueKeysWithValues: folders.flatMap { $0.items(.needs) }.enumerated().map { ($1.id, $0 + 1) })
        GeometryReader { geometry in
            let widths = LaneWidths(width: geometry.size.width)
            Scrolling {
                grid(folders: folders, page: page, visits: visits, widths: widths)
            }
        }
    }

    private func grid(folders: [CanvasFolder], page: RouterPage, visits: [String: Int], widths: LaneWidths) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Section {
                    ForEach(folders) { folder in
                        LaneRow(store: store, model: model, page: page, folder: folder, visits: visits, widths: widths,
                                brief: brief(folder, page: page))
                        Rectangle().fill(CDS.border).frame(height: CDS.hairline)
                    }
                    let done = model.canvasFolders(store, page: page).filter(\.doneOnly)
                    if !done.isEmpty {
                        Text("Nothing open in " + done.map(\.name).joined(separator: ", "))
                            .font(CDS.sans(12)).foregroundStyle(CDS.Text.muted)
                            .padding(.horizontal, LaneMetrics.rowPad).padding(.vertical, 12)
                    }
                } header: {
                    LaneHeader(folders: folders, widths: widths)
                }
            }
            .padding(.bottom, LaneMetrics.bottom)
    }

    /// Where the project stands: its newest summary of a session at work, else the newest finished card's brief. Not a card
    /// of its own that needs you: that card says it already. (A stand-in for a status the Router would write per project.)
    private func brief(_ folder: CanvasFolder, page: RouterPage) -> String? {
        let sessions = Set(folder.groups.flatMap { $0.items.map(\.sessionID) })
        if let s = store.router.summaries.filter({ $0.sessionID.map(sessions.contains) == true }).max(by: { $0.at < $1.at }) {
            return s.text
        }
        let cards = folder.groups.filter { $0.group != .needs }.flatMap(\.items).compactMap { item -> RouterCard? in
            switch item {
            case .done(let c): c
            default: nil
            }
        }
        return cards.max { $0.createdAt < $1.createdAt }.map { $0.brief ?? $0.text }
    }
}

/// A scroll view, or in a shot run the content flat from the top: the shots' capture doesn't draw a scroll view's content
/// on the Router's page (why the list's shots come out empty).
private struct Scrolling<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if ShotRun.active {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView { content }
        }
    }
}

/// The columns' names over the grid, pinned as it scrolls, each with its count across every project.
private struct LaneHeader: View {
    let folders: [CanvasFolder]
    let widths: LaneWidths

    var body: some View {
        HStack(alignment: .center, spacing: LaneMetrics.gap) {
            Text("\(folders.count) projects")
                .font(CDS.sans(12, .medium)).foregroundStyle(CDS.Text.muted)
                .frame(width: widths.gutter, alignment: .leading)
            ForEach(LaneColumn.allCases) { column in
                let count = folders.reduce(0) { $0 + $1.items(column).count }
                HStack(spacing: 5) {
                    Image(systemName: column.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(column.tint)
                    Text(column.title).font(CDS.sans(12, .medium)).foregroundStyle(CDS.Text.secondary)
                    Text("\(count)").font(CDS.sans(12, .medium)).foregroundStyle(count > 0 && column == .needs ? column.tint : CDS.Text.muted)
                }
                .frame(width: column == .needs ? widths.needs + VisitBadge.size + 8 : widths.side, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LaneMetrics.rowPad)
        .frame(height: 36)
        .background(CDS.Surface.s1)
        .overlay(alignment: .bottom) { Rectangle().fill(CDS.border).frame(height: CDS.hairline) }
    }
}

/// One project's row: its name and where it stands, then its columns.
private struct LaneRow: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage
    let folder: CanvasFolder
    let visits: [String: Int]
    let widths: LaneWidths
    let brief: String?

    var body: some View {
        HStack(alignment: .top, spacing: LaneMetrics.gap) {
            gutter.frame(width: widths.gutter, alignment: .leading)
            needs
            column(.notes)
            column(.running)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LaneMetrics.rowPad)
        .padding(.vertical, folder.quiet ? 10 : LaneMetrics.rowPad)
        .background(folder.quiet ? Color.clear : (folder.color ?? CDS.Text.muted).opacity(0.035))
        .overlay(alignment: .leading) {
            Rectangle().fill(folder.color ?? CDS.Text.muted).frame(width: 3)
        }
    }

    private var gutter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(folder.color ?? CDS.Text.muted).frame(width: 8, height: 8)
                Text(folder.name.isEmpty ? "Scratch" : folder.name)
                    .font(CDS.sans(14, .semibold)).foregroundStyle(CDS.Text.primary).lineLimit(1)
            }
            if !folder.quiet, let brief {
                Text(LocalizedStringKey(brief))
                    .font(CDS.sans(12)).foregroundStyle(CDS.Text.secondary)
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            if folder.doneCount > 0 {
                Label("\(folder.doneCount) done", systemImage: "checkmark")
                    .font(CDS.sans(11)).foregroundStyle(CDS.Text.muted).labelStyle(.titleAndIcon)
            }
        }
    }

    @ViewBuilder private var needs: some View {
        let items = folder.items(.needs)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    VisitBadge(number: visits[item.id] ?? 0)
                    CanvasNode(item: item, store: store, model: model, page: page)
                        .frame(width: widths.needs, alignment: .leading)
                }
            }
            if items.isEmpty {
                Text("Nothing for you")
                    .font(CDS.sans(12)).foregroundStyle(CDS.Text.muted)
                    .padding(.leading, VisitBadge.size + 8).padding(.top, 2)
            }
        }
        .frame(width: widths.needs + VisitBadge.size + 8, alignment: .leading)
    }

    private func column(_ column: LaneColumn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(folder.items(column)) { item in
                LaneLine(store: store, page: page, item: item)
            }
        }
        .frame(width: widths.side, alignment: .leading)
    }
}

/// A card's place in the visit order; the first is Next.
struct VisitBadge: View {
    let number: Int
    static let size: CGFloat = 22

    var body: some View {
        Text("\(number)")
            .font(CDS.sans(11, .semibold))
            .foregroundStyle(number == 1 ? Color.white : RouterZone.needs.tint)
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(number == 1 ? RouterZone.needs.tint : RouterZone.needs.tint.opacity(0.14)))
            .padding(.top, 8)
            .accessibilityLabel(number == 1 ? "Next" : "Visit \(number)")
    }
}

/// A session that doesn't need you, in a line or two: what it is, how long ago, and what it's at.
private struct LaneLine: View {
    let store: Store
    let page: RouterPage
    let item: CanvasItem

    var body: some View {
        let (symbol, tint, title, detail, at) = parts
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint).frame(width: 12)
                Text(title).font(CDS.sans(12.5, .medium)).foregroundStyle(CDS.Text.primary).lineLimit(1)
                Spacer(minLength: 4)
                Text(shortAgo(at)).font(CDS.sans(11)).foregroundStyle(CDS.Text.muted).monospacedDigit()
            }
            if let detail, !detail.isEmpty {
                Text(LocalizedStringKey(detail)).font(CDS.sans(11.5)).foregroundStyle(CDS.Text.secondary)
                    .lineLimit(2).padding(.leading, 18)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CDS.alpha(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
    }

    private var parts: (String, Color, String, String?, Date) {
        switch item {
        case .working(let row):
            let summary = page.summaries[row.id]?.text
            return (RouterZone.working.symbol, CDS.Text.muted, row.session.title, row.activity?.text ?? summary,
                    row.activity?.since ?? row.session.lastActivity)
        case .waiting(let c):
            let on = c.triage?.watch?.label ?? c.text
            return (RouterZone.waiting.symbol, RouterZone.waiting.tint, c.title, "Waiting on " + on, c.createdAt)
        case .note(let c):
            return (RouterZone.notes.symbol, RouterZone.notes.tint, c.title, c.brief ?? c.text, c.createdAt)
        case .need(let c), .ready(let c), .done(let c):
            return ("circle", CDS.Text.muted, c.title, c.brief ?? c.text, c.createdAt)
        }
    }
}
