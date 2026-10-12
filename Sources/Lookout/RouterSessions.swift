import AppKit
import SwiftUI

// What the Router shows of a Claude session: its icon (or letters) and status dot, its project, what it left running, and
// the menu on its rows.

extension ClaudeDot.Kind {
    /// A session's dot, as Claude's list draws it: needs you, done and unread, working (or left something running), else
    /// the quiet hollow ring.
    init(_ row: AgentRow) {
        switch row.group {
        case .needsYou: self = .needsYou
        case .done: self = .done
        case .working: self = .working
        case .idle: self = .quiet
        }
    }
}

/// Claude's session status dot (§1.7), 6pt in a 14pt box: awaiting #fab219 (a question or a plan), ready #2a78d6 (a
/// finished turn), running #898781 blinking (a working session), idle a 1pt hollow ring at 50% (addressed). Claude has no
/// "stuck" state; Lookout's stuck card keeps a red 6pt dot (`CDS.Text.danger`).
struct ClaudeDot: View {
    enum Kind {
        case needsYou, done, stuck, working, waiting, quiet

        init(_ card: RouterCard) {
            guard card.isOpen else { self = .quiet; return }
            switch card.kind {
            case .question, .plan, .asks, .approval, .finish: self = .needsYou
            case .stuck: self = .stuck
            case .done: self = .done
            case .waiting: self = .waiting
            }
        }
    }

    let kind: Kind

    var body: some View {
        ZStack {
            switch kind {
            case .needsYou: Circle().fill(CDS.Fill.warning).frame(width: 6, height: 6)
            case .done: Circle().fill(CDS.Fill.accent).frame(width: 6, height: 6)
            case .stuck: Circle().fill(CDS.Text.danger).frame(width: 6, height: 6)
            case .waiting: Circle().fill(RouterTriage.waitingTint).frame(width: 6, height: 6)
            case .quiet: Circle().strokeBorder(CDS.Text.muted, lineWidth: 1).frame(width: 6, height: 6).opacity(0.5)
            case .working: BlinkingDot()
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

/// `dframe-dot-blink`: 1.2s ease-in-out, opacity .3 → 1 → .3, forever; lit and still with Reduce Motion.
private struct BlinkingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false
    var body: some View {
        Circle().fill(CDS.Text.muted).frame(width: 6, height: 6)
            .opacity(lit ? 1 : 0.3)
            .onAppear {
                let blink = Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                withAnimation(blink.resolved(reduce: reduceMotion)) { lit = true }
            }
    }
}

/// A session's face in the Router's lists: the icon Jev picked (else its letters, or an emoji) on a neutral square, in the
/// project's colour, with Claude's status dot on its corner when `dot` is on. Without a session behind it, nothing.
struct SessionGlyph: View {
    let row: AgentRow
    var size: CGFloat = 18
    var dot = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CDS.Tile.radius * size / CDS.Tile.size + 1, style: .continuous)
        let kind = ClaudeDot.Kind(row)
        let emoji = row.label.unicodeScalars.first.map { $0.properties.isEmoji && $0.value > 0xFF } ?? false
        Group {
            if let icon = row.icon {
                Image(systemName: icon).font(.system(size: size * 0.6, weight: .medium)).symbolRenderingMode(.monochrome)
            } else {
                Text(row.label)
                    .font(emoji ? .system(size: size * 0.55) : CDS.sans(size * 0.45, .medium))
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
        }
        .foregroundStyle(row.color ?? CDS.Text.secondary)
        .frame(width: size, height: size)
        .background(shape.fill(CDS.Tile.fill))
        .overlay(alignment: .topTrailing) {
            if dot, kind != .quiet {
                ClaudeDot(kind: kind)
                    .scaleEffect(0.8)
                    .background(Circle().fill(Theme.bg).frame(width: 9, height: 9))
                    .offset(x: 5, y: -5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A project's colour dot and name.
struct ProjectLabel: View {
    let name: String
    let color: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let color {
                Circle().fill(color).frame(width: 6, height: 6)
            } else {
                Image(systemName: "text.bubble").font(.system(size: 9, weight: .medium))
            }
            Text(name)
        }
    }
}

/// A session's context menu in the Router: open it, fork it, pick it another icon, give its project a colour, mute the project.
struct SessionMenu: View {
    let row: AgentRow
    let store: Store

    var body: some View {
        Button("Open in Claude") { store.openAgent(row.id) }
        // A new session that continues from this one's conversation (files aren't forked).
        if store.routerOn, row.session.cliID != nil {
            Button("Fork") { store.forkSession(row.id) }
            Button("Fork from before your last message") { store.forkSession(row.id, point: .beforeLast) }
        }
        if store.canPickIcons && row.entry.label == nil {
            Button(row.entry.icon == nil ? "Pick an icon" : "Pick another icon") { store.repickIcon(row.id) }
        }
        if !row.session.folderKey.isEmpty {
            Menu("Colour for \(row.projectName)") {
                ForEach(Theme.projectColorNames.indices, id: \.self) { i in
                    Button(Theme.projectColorNames[i]) { store.setProjectColor(row.session.folderKey, i) }
                }
            }
        }
        // A session found through search can be of a project muted already: muting it again would do nothing.
        if store.isFolderMuted(row.session.folderKey) {
            Button("Unmute \(row.projectName)") { store.setFolderMuted(row.session.folderKey, false) }
        } else {
            Button("Mute \(row.projectName)") { store.setFolderMuted(row.session.folderKey, true) }
        }
    }
}

extension Store {
    /// The row of a session, listed or not (a card's, say).
    func sessionRow(_ id: String) -> AgentRow? { claudeSessions[id].map { row($0) } }
}

/// The Claude link's state as a dot and a line ("Synced with Claude", "Claude's sessions not found"…).
struct ClaudeLinkStatus: View {
    let store: Store

    var body: some View {
        let (color, text, detail): (Color, String, String) = switch store.claudeLink {
        case .ok where Claude.isRunning: (Theme.green, "Synced with Claude", "Updates as the Claude app writes its session files")
        case .ok, .off: (Theme.tertiary, "Claude isn't running", "Sessions update again when the app is open")
        case .missing: (Theme.red, "Claude's sessions not found", "Open the Claude desktop app once")
        case .unreadable: (Theme.red, "Can't read Claude's sessions", "The app's session format changed")
        }
        Circle().fill(color).frame(width: 6, height: 6)
        Text(text).tip(text, detail)
    }
}

/// "N API calls left this hour", only when the shared GitHub rate limit is running low.
struct RateLimitWarning: View {
    let store: Store

    var body: some View {
        if let rate = store.rateRemaining, rate < 500 {
            Label("\(rate.formatted()) API calls left this hour", systemImage: "exclamationmark.triangle.fill")
                .monospacedDigit()
                .foregroundStyle(Theme.amber)
                .tip("GitHub rate limit low",
                     "Shared with gh and other tools. Syncing pauses at 0.")
        }
    }
}

extension EnvironmentValues {
    /// Playground only: force a tooltip to show.
    @Entry var previewTip: String? = nil
}

extension View {
    /// What a session left running, by name, in a tooltip (nothing when it left nothing).
    @ViewBuilder func runningTip(_ tasks: [ClaudeTask]) -> some View {
        if tasks.isEmpty { self } else { tip("Running", tasks.map(\.title).joined(separator: "\n")) }
    }
}
