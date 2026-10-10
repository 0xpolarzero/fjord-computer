import SwiftUI

// The Router's transcripts as Claude's Code tab draws its own (docs/design/spec/transcript.md, compact density, text
// 14/20): your words in the user bubble, the Router's as assistant prose, what it sent as a collapsed TurnStatus line,
// a session's reply as a summary card, an error as the danger banner, and the clay working mark while it works.

// MARK: - Transcript

/// A card's side of things: what the session said, the form or plan it waits on, what it left running, then what you, the
/// Router and the session said about it since.
struct CardTranscript: View {
    let store: Store
    @Bindable var model: RouterModel
    let card: RouterCard
    @State private var width = CDS.Transcript.measure

    var body: some View {
        let form = store.pendingForm(for: card)
        let tasks = store.allAgentRows.first(where: { $0.id == card.sessionID })?.tasks ?? []
        let chat = store.router.chat.filter { $0.sessionID == card.sessionID || $0.replyTo == card.id }
        VStack(alignment: .leading, spacing: 0) {
            // The card's own turn: its text, its form, what it left running (AssistantMessage blocks, 16 apart).
            VStack(alignment: .leading, spacing: CDS.Transcript.blockGap) {
                // With a form open, the form says it (the card's text is its question or the plan's title).
                if form == nil || !card.isOpen {
                    CDSProse(text: card.text, color: card.kind == .stuck ? CDS.Text.danger : CDS.Text.primary)
                }
                if let form, card.isOpen {
                    if form.isPlan { CodePlanCard(form: form, card: card.id, store: store, model: model) }
                    else { CodeFormCard(form: form, card: card.id, store: store, model: model) }
                }
                if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tasks) { task in
                            TurnStatusRow(label: task.title, meta: task.activity?.text, leading: true)
                        }
                    }
                }
                if let by = card.addressedBy { TurnStatusRow(label: by.label) }
            }
            ForEach(Array(chat.enumerated()), id: \.element.id) { i, message in
                CodeMessage(message: message, store: store)
                    .padding(.top, CodeMessage.gap(before: message, after: i == 0 ? nil : chat[i - 1].role, first: false))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(\.cdsColumnWidth, width)
    }
}

/// The Router's own conversation.
struct RouterTranscript: View {
    let store: Store
    @State private var width = CDS.Transcript.measure

    var body: some View {
        let chat = store.router.chat
        let agent = store.routerAgent
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chat.enumerated()), id: \.element.id) { i, message in
                CodeMessage(message: message, store: store)
                    .padding(.top, CodeMessage.gap(before: message, after: i == 0 ? nil : chat[i - 1].role, first: i == 0))
                    .id(message.id)
            }
            if agent.phase == .working || agent.phase == .starting {
                WorkingStatus(label: agent.phase == .starting ? "Starting" : "Working")
                    .padding(.top, chat.isEmpty ? 0
                             : chat.last?.role == .you ? CDS.Transcript.userTurnBottom : CDS.Transcript.itemGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(\.cdsColumnWidth, width)
    }
}

/// A line of the conversation as the Code tab shows it.
struct CodeMessage: View {
    let message: RouterMessage
    let store: Store

    private var session: String? { message.sessionID.flatMap { store.claudeSessions[$0]?.title } }

    /// §1's rhythm: 10 between rows of a turn, the measured user-turn spacing around your bubble, the banner's 16.
    static func gap(before message: RouterMessage, after previous: RouterMessage.Role?, first: Bool) -> CGFloat {
        guard let previous else { return first ? 0 : CDS.Transcript.blockGap }
        if message.role == .you { return previous == .you ? CDS.Transcript.turnGap : CDS.Transcript.userTurnTop }
        if previous == .you { return CDS.Transcript.userTurnBottom }
        if message.role == .error { return CDS.Transcript.blockGap }
        return CDS.Transcript.itemGap
    }

    var body: some View {
        switch message.role {
        case .you:
            UserBubble(message: message)
        case .router:
            CDSProse(text: message.text)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Router: \(message.text)")
        case .receipt:
            ReceiptStatus(message: message, store: store, session: session)
        case .peer:
            PeerCard(title: session ?? "A session", text: message.text)
        case .error:
            DangerBanner(text: message.text)
        case .automated:
            AutomatedMessage(message: message)
        case .change:
            if let change = message.change { ChangeCard(change: change, store: store) } else { ReceiptStatus(message: message, store: store, session: nil) }
        }
    }

    /// A receipt says "→ Title: what was sent"; the line already names the session, so only what was sent.
    static func sent(_ text: String) -> String {
        guard text.hasPrefix("→"), let colon = text.firstIndex(of: ":") else { return text }
        return text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    /// The title a receipt's text names ("→ Title: …"), for a session Lookout no longer lists.
    static func named(_ text: String) -> String? {
        guard text.hasPrefix("→"), let colon = text.firstIndex(of: ":") else { return nil }
        let title = text[text.index(after: text.startIndex)..<colon].trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }
}

// MARK: - Width

private struct ColumnWidthKey: EnvironmentKey { static let defaultValue = CDS.Transcript.measure }

extension EnvironmentValues {
    /// The transcript column's content width, for the prose's text stop and the bubble's 85%.
    var cdsColumnWidth: CGFloat {
        get { self[ColumnWidthKey.self] }
        set { self[ColumnWidthKey.self] = newValue }
    }
}

// MARK: - Prose

/// §3 assistant prose: 14/20 at wght 360, paragraphs .75em apart, lists indented 2em with secondary markers, `strong` at
/// 560, inline code in danger red on white 5%, links in accent; 4 in from the start, the text stop from the end.
struct CDSProse: View {
    let text: String
    var color: Color = CDS.Text.primary
    /// Inside a card the insets reset to 0.
    var inset = true
    @Environment(\.cdsColumnWidth) private var width

    private enum Block { case paragraph(String), list([String], ordered: Bool) }

    var body: some View {
        let blocks = Self.blocks(text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                Group {
                    switch block {
                    case .paragraph(let p):
                        line(p)
                    case .list(let items, let ordered):
                        VStack(alignment: .leading, spacing: CDS.Transcript.itemFlow) {
                            ForEach(Array(items.enumerated()), id: \.offset) { n, item in
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text(ordered ? "\(n + 1)." : "•").cdsText(CDS.Transcript.text, .regular, CDS.Text.secondary)
                                        .frame(width: CDS.Transcript.listIndent - 6, alignment: .trailing)
                                        .padding(.trailing, 6)
                                    line(item).padding(.leading, CDS.Transcript.itemPad - (inset ? CDS.Transcript.textInset : 0))
                                }
                            }
                        }
                    }
                }
                .padding(.top, i == 0 ? 0 : Self.isList(blocks[i - 1]) ? CDS.Transcript.flow * 2 : CDS.Transcript.flow)
            }
        }
        .padding(.leading, inset ? CDS.Transcript.textInset : 0)
        .padding(.trailing, inset ? CDS.Transcript.textStop(width) : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ s: String) -> some View {
        Text(Self.attributed(s, color: color))
            .cdsText(CDS.Transcript.text, .regular, color)
            .tint(CDS.Text.accent)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private static func isList(_ b: Block) -> Bool { if case .list = b { true } else { false } }

    /// Blank lines split paragraphs; a run of "- ", "* " or "1. " lines is a list.
    private static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        for chunk in text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n\n") {
            let lines = chunk.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard !lines.isEmpty else { continue }
            let bullets = lines.compactMap(bullet)
            if bullets.count == lines.count {
                out.append(.list(bullets.map(\.text), ordered: bullets[0].ordered))
            } else {
                out.append(.paragraph(chunk))
            }
        }
        return out.isEmpty ? [.paragraph(text)] : out
    }

    private static func bullet(_ line: String) -> (text: String, ordered: Bool)? {
        let t = line.drop { $0 == " " }
        if t.hasPrefix("- ") || t.hasPrefix("* ") { return (String(t.dropFirst(2)), false) }
        if let dot = t.firstIndex(of: "."), !t[..<dot].isEmpty, t[..<dot].allSatisfy(\.isNumber),
           t[t.index(after: dot)...].hasPrefix(" ") {
            return (String(t[t.index(dot, offsetBy: 2)...]), true)
        }
        return nil
    }

    /// The inline Markdown with Claude's prose styles set run by run (Anthropic Sans's weights are variable axes, so
    /// SwiftUI's own bold would not reach 560).
    static func attributed(_ s: String, color: Color = CDS.Text.primary) -> AttributedString {
        var out = RouterText.inline(s)
        for run in out.runs {
            let intent = run.inlinePresentationIntent ?? []
            let range = run.range
            if intent.contains(.code) {
                out[range].font = CDS.mono(CDS.Transcript.codeSize)
                out[range].foregroundColor = CDS.Text.danger
                out[range].backgroundColor = CDS.Transcript.codeFill
                continue
            }
            var font = CDS.sans(CDS.Transcript.text.0, intent.contains(.stronglyEmphasized) ? .bold : .regular)
            if intent.contains(.emphasized) { font = font.italic() }
            out[range].font = font
            if intent.contains(.strikethrough) {
                out[range].strikethroughStyle = Text.LineStyle(pattern: .solid, color: color.opacity(0.6))
            }
            if run.link != nil {
                out[range].foregroundColor = CDS.Text.accent
                out[range].underlineStyle = Text.LineStyle(pattern: .solid, color: CDS.Text.accent.opacity(0.4))
            }
        }
        // §3 inline code's .25em side padding: a thin space on white 5% either side.
        var padded = AttributedString()
        var lastWasCode = false
        for run in out.runs {
            let isCode = (run.inlinePresentationIntent ?? []).contains(.code)
            if isCode != lastWasCode { padded += pad(code: true) }
            padded += AttributedString(out[run.range])
            lastWasCode = isCode
        }
        if lastWasCode { padded += pad(code: true) }
        return padded
    }

    private static func pad(code: Bool) -> AttributedString {
        var s = AttributedString("\u{2009}")
        s.font = CDS.sans(CDS.Transcript.text.0)
        s.backgroundColor = CDS.Transcript.codeFill
        return s
    }
}

// MARK: - User bubble

/// §2: trailing, at most 85% of the column, 12 × 8, radius 10, white 5%, 14/20 primary; it pops in (0.45 s from 0.92 and
/// 6 down, overshooting) when it is new.
private struct UserBubble: View {
    let message: RouterMessage
    @Environment(\.cdsColumnWidth) private var width
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = true

    var body: some View {
        Text(message.text)
            .cdsText(CDS.Transcript.text)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, CDS.Transcript.bubblePadX)
            .padding(.vertical, CDS.Transcript.bubblePadY)
            .background(RoundedRectangle(cornerRadius: CDS.Transcript.bubbleRadius, style: .continuous)
                .fill(CDS.Transcript.bubbleFill))
            .scaleEffect(shown ? 1 : 0.92, anchor: .trailing)
            .offset(y: shown ? 0 : 6)
            .opacity(shown ? 1 : 0)
            .frame(maxWidth: width * CDS.Transcript.bubbleMeasure, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You: \(message.text)")
            .onAppear {
                guard !reduceMotion, Date().timeIntervalSince(message.date) < 1.5 else { return }
                shown = false
                withAnimation(.timingCurve(0.34, 1.3, 0.64, 1, duration: 0.45)) { shown = true }
            }
    }
}

/// A category's action asking the Router: "⚡ Category" over what it said, in no bubble (it isn't you).
private struct AutomatedMessage: View {
    let message: RouterMessage

    private var source: String { message.source ?? "An action" }
    private var body_: String {
        let prefix = "⚡ \(source): "
        return message.text.hasPrefix(prefix) ? String(message.text.dropFirst(prefix.count)) : message.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚡ \(source)").cdsText(CDS.Transcript.text, .medium, CDS.Text.secondary)
            Text(body_).cdsText(CDS.Transcript.text, .regular, CDS.Text.muted)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .padding(.horizontal, CDS.Transcript.bubblePadX).padding(.vertical, CDS.Transcript.bubblePadY)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: CDS.Transcript.bubbleRadius, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Action from \(source): \(body_)")
    }
}

// MARK: - TurnStatus

/// The caret after a status label: 12 box, a ≈4 × 7 glyph, muted (secondary on hover or open), a quarter turn open.
private struct StatusCaret: View {
    let hot: Bool
    let open: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(hot || open ? CDS.Text.secondary : CDS.Text.muted)
            .rotationEffect(.degrees(open ? 90 : 0))
            .animation(.easeOut(duration: 0.06), value: open)
            .frame(width: CDS.Transcript.caretBox, height: CDS.Transcript.text.1)
            .accessibilityHidden(true)
    }
}

/// §4 a TurnStatus line that opens nothing: a 24 row, the muted label lined up with the prose, an optional primary meta.
struct TurnStatusRow: View {
    let label: String
    var meta: String? = nil
    /// The clay working mark before it (a task still running).
    var leading = false

    var body: some View {
        HStack(spacing: CDS.Density.compact.gap.xs) {
            if leading { WorkingMark() }
            Text(label).cdsText(CDS.Transcript.text, .regular, CDS.Text.muted).lineLimit(1).layoutPriority(1)
            if let meta { Text(meta).cdsText(CDS.Transcript.text).lineLimit(1).truncationMode(.tail) }
        }
        .padding(.horizontal, CDS.Transcript.statusPad)
        .frame(minHeight: CDS.Transcript.statusRow)
        .padding(.leading, CDS.Transcript.textInset - CDS.Transcript.statusPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// What the Router sent, as "Ran N commands ›": "Sent to <session>" in muted, opening (§5) onto a card of what went, and
/// what you wrote when Lookout rephrased it.
private struct ReceiptStatus: View {
    let message: RouterMessage
    let store: Store
    let session: String?
    @State private var open = false
    @State private var hovered = false
    @FocusState private var focused: Bool
    @Environment(\.cdsColumnWidth) private var width

    var body: some View {
        let title = session ?? CodeMessage.named(message.text)
        let label = title.map { "Sent to \($0)" } ?? message.text
        let expandable = title != nil
        VStack(alignment: .leading, spacing: 0) {
            Button { if expandable { open.toggle() } } label: {
                HStack(spacing: CDS.Density.compact.gap.xs - 4) {
                    Text(label)
                        .cdsText(CDS.Transcript.text, .regular, hovered || (open && expandable) ? CDS.Text.secondary : CDS.Text.muted)
                        .lineLimit(1).truncationMode(.tail)
                    if expandable { StatusCaret(hot: hovered, open: open) }
                }
                .padding(.horizontal, CDS.Transcript.statusPad)
                .frame(height: CDS.Transcript.statusRow)
                .contentShape(Rectangle())
                .overlay {
                    RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                        .strokeBorder(CDS.Fill.accent, lineWidth: 1).opacity(focused ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .focused($focused)
            .onHover { hovered = $0 }
            .padding(.leading, CDS.Transcript.textInset - CDS.Transcript.statusPad)
            .accessibilityLabel(label)
            .accessibilityValue(expandable ? (open ? "Expanded" : "Collapsed") : "")
            .accessibilityAction(named: "Open in Claude") { if let id = message.sessionID { store.openAgent(id) } }

            if open, expandable {
                VStack(alignment: .leading, spacing: 0) {
                    cell(CDSProse.attributed(CodeMessage.sent(message.text), color: CDS.Text.secondary), CDS.Text.secondary)
                    if let original = message.original {
                        Rectangle().fill(CDS.border).frame(height: 1)
                        cell(AttributedString("You wrote: \(original)"), CDS.Text.muted)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CDS.Transcript.stepCardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CDS.Transcript.stepCardRadius, style: .continuous)
                        .strokeBorder(CDS.border, lineWidth: 1)
                }
                .padding(.top, CDS.Density.compact.pad.sm)
                .padding(.bottom, CDS.Density.compact.pad.xs)
                .padding(.trailing, CDS.Transcript.textStop(width))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ text: AttributedString, _ color: Color) -> some View {
        Text(text)
            .cdsText(CDS.Transcript.text, .regular, color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, CDS.Transcript.cellPadX)
            .padding(.vertical, CDS.Transcript.cellPadY)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Cards and banners

/// A session's reply, as §9's summary card: radius 10, an inset white-10% ring, a 24 header naming the session over a
/// divider, then the reply as prose.
private struct PeerCard: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: CDS.Density.compact.pad.xs) {
            HStack(spacing: CDS.Density.compact.gap.xs) {
                Image(systemName: "laptopcomputer").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CDS.Text.muted).frame(width: 16, height: 16).accessibilityHidden(true)
                Text(title).cdsText(CDS.Transcript.text).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: CDS.Density.compact.gap.sm)
                Text("replied").cdsText(CDS.Transcript.text, .regular, CDS.Text.muted)
            }
            .padding(.horizontal, CDS.Density.compact.pad.xs)
            .frame(height: CDS.Density.compact.control)
            Rectangle().fill(CDS.border).frame(height: 1)
                .padding(.horizontal, -(CDS.Transcript.cardPadX - 1))
            CDSProse(text: text, inset: false)
                .padding(.horizontal, CDS.Density.compact.pad.xs)
                .padding(.top, 2).padding(.bottom, CDS.Density.compact.pad.xs)
        }
        .padding(.horizontal, CDS.Transcript.cardPadX)
        .padding(.vertical, CDS.Transcript.cardPadY)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: CDS.Transcript.cardRadius, style: .continuous).strokeBorder(CDS.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) replied: \(text)")
    }
}

/// §8 the danger banner: #3c0e0e, its #641919 ring, radius 10, 12 × 8, the warning glyph and the text in #ec7e7e, set 4
/// out on either side.
private struct DangerBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: CDS.Density.compact.gap.xs) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .medium))
                .frame(height: CDS.Transcript.text.1).accessibilityHidden(true)
            Text(text).cdsText(CDS.Transcript.text, .regular, CDS.Text.danger)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(CDS.Text.danger)
        .padding(.horizontal, CDS.Density.compact.pad.lg)
        .padding(.vertical, CDS.Density.compact.pad.md)
        .background(RoundedRectangle(cornerRadius: CDS.Transcript.cardRadius, style: .continuous).fill(CDS.Transcript.dangerFill))
        .overlay {
            RoundedRectangle(cornerRadius: CDS.Transcript.cardRadius, style: .continuous)
                .strokeBorder(CDS.Transcript.dangerRing, lineWidth: 1)
        }
        .padding(.horizontal, -CDS.Transcript.statusPad)
        .padding(.bottom, CDS.Density.compact.pad.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(text)")
    }
}

// MARK: - Working

/// §7: the clay mark in its 20 box, then the label in muted with the sheen passing over it.
private struct WorkingStatus: View {
    let label: String

    var body: some View {
        HStack(spacing: CDS.Density.compact.gap.xs) {
            WorkingMark()
            ShimmerText(text: label)
        }
        .frame(height: CDS.Transcript.statusRow)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// The clay working mark: three dots at the start of a 20 box, the brightest one stepping along (still, the middle one,
/// as the sprite's frame in the reference).
struct WorkingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
            let lit = reduceMotion ? 1 : Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: CDS.Transcript.markDots.pitch - CDS.Transcript.markDots.size) {
                ForEach(0..<3) { i in
                    Circle().fill(CDS.clay.opacity(i == lit ? 1 : 0.55))
                        .frame(width: CDS.Transcript.markDots.size, height: CDS.Transcript.markDots.size)
                }
            }
            .frame(width: CDS.Transcript.markBox, height: CDS.Transcript.markBox, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

/// §7's shimmer: muted text, a sheen one text-width wide sweeping across in 3 s (held 15% at either end).
private struct ShimmerText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let c = reduceMotion ? -1 : Self.centre(context.date.timeIntervalSinceReferenceDate)
            Text(text)
                .cdsText(CDS.Transcript.text, .regular, CDS.Text.muted)
                .foregroundStyle(LinearGradient(
                    stops: [.init(color: CDS.Text.muted, location: 0), .init(color: CDS.Transcript.shimmerPeak, location: 0.5),
                            .init(color: CDS.Text.muted, location: 1)],
                    startPoint: UnitPoint(x: c - 0.5, y: 0.3), endPoint: UnitPoint(x: c + 0.5, y: 0.7)))
                .lineLimit(1)
        }
    }

    /// The sheen's centre in text widths: −0.5 to 1.5, eased `cubic-bezier(.714,.121,.211,.888)` over 15–85%.
    static func centre(_ t: Double) -> Double {
        let f = t.truncatingRemainder(dividingBy: CDS.Transcript.shimmerPeriod) / CDS.Transcript.shimmerPeriod
        let p = min(1, max(0, (f - 0.15) / 0.7))
        return -0.5 + 2 * bezier(p, 0.714, 0.121, 0.211, 0.888)
    }

    private static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func coord(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t }
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if coord(mid, x1, x2) < x { lo = mid } else { hi = mid }
        }
        return coord((lo + hi) / 2, y1, y2)
    }
}

// MARK: - Top fade

extension View {
    /// §1's sticky fade strip over a transcript: 32 tall, #151515 to clear, fading in over the first 32 of scroll.
    func cdsTopFade() -> some View { modifier(TopFade()) }
}

private struct TopFade: ViewModifier {
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        let s = CDS.Surface.s1
        let strip = LinearGradient(stops: [.init(color: s, location: 0), .init(color: s.opacity(0.85), location: 0.13),
                                           .init(color: s.opacity(0.5), location: 0.4), .init(color: s.opacity(0.15), location: 0.7),
                                           .init(color: s.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
            .frame(height: CDS.Transcript.fade)
            .allowsHitTesting(false)
        if #available(macOS 15, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { offset = $1 }
                .overlay(alignment: .top) { strip.opacity(min(1, max(0, offset / CDS.Transcript.fade))) }
        } else {
            content.overlay(alignment: .top) { strip }
        }
    }
}
