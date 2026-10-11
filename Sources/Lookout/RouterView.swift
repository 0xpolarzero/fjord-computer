import AppKit
import SwiftUI

// What the Router's window is built on (`RouterCodeView` lays it out): the store's side of the Router, the cards' lines and
// tags, the window's model (the pick, the draft, its chips and @, the forms and plans being answered), the notice of what
// stands in the way, and the Working list the bar shows.

// MARK: - Store

extension Store {
    /// The Router works on the sessions: it is on only while Lookout reads them too (they follow its switch).
    var routerOn: Bool { router.enabled && agents.enabled }

    /// A card's project, as the lists name and colour it.
    func routerProject(_ card: RouterCard) -> (name: String, color: Color?) {
        let folder = card.folder ?? ""
        return (folderName(folder), projectColor(folder))
    }

    /// The Router's switch: it turns the reading of Claude's sessions, which it works on, on and off with it.
    func switchRouter(_ on: Bool) {
        if on { setAgentsEnabled(true) }
        setRouterEnabled(on)
        if !on { setAgentsEnabled(false) }
    }

    /// The sessions working now (not those stopped on you), and those whose turn is over with subagents or commands still
    /// running (the tiles count them as working too); the longest running first.
    var routerWorkingRows: [AgentRow] {
        allAgentRows.filter { ($0.session.running && !$0.waitsForYou) || (!$0.session.running && !$0.tasks.isEmpty) }
            .sorted { (Self.workingStart($0) ?? .distantFuture) < (Self.workingStart($1) ?? .distantFuture) }
    }

    /// Since when a row in the Working list works: its turn, or the oldest thing it left running.
    static func workingStart(_ row: AgentRow) -> Date? {
        row.session.running ? row.workingSince : row.tasks.map(\.since).min()
    }

    /// The Router's own process must never reach real sessions from a demo or a playground: it answers for itself there.
    var routerIsPretend: Bool { Store.isDemo || !persists }

    /// Your message to the Router, with the card it replies to and the projects you tagged; in a demo, a canned reply
    /// instead of a real process.
    func sendToRouter(_ text: String, context: RouterContext = RouterContext(), now: Date = Date()) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if routerIsPretend {
            var entry = RouterDecision(at: now, trigger: .you(text), decision: .init(intent: "message"), outcome: .done,
                                       links: .init(cards: context.replyTo.map { [$0] } ?? []))
            entry.reply = "In a demo the Router only says what it would do."
            logDecision(entry)
        } else {
            routerDispatcher.submit(text, context: context)
        }
    }

    /// Writes a form's answer for its card's session (the hook passes it on) through the shared `FormWriter`, off the main
    /// thread; in a demo, nothing is written. The folder is taken now, on the main thread: none while the Router is off. The
    /// write is dropped if, by the time it happens, the Router or the sessions are off or the card is no longer open.
    func answerForm(_ form: PendingForm, _ answers: [String: String], card: String) async -> Result<Void, Error> {
        if routerIsPretend { return Result { _ = try FormBridge.validate(form, answers) } }
        guard let dir = formBridge.dir else { return .failure(FormWriter.Cancelled()) }
        do {
            try await FormWriter.write(form, answers: answers, dir: dir) { [weak self] in
                guard let self else { return false }
                return self.routerOn && self.router.cards.first(where: { $0.id == card })?.isOpen == true
            }
            logCardAction("Answered the form", card: card)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// The same for a plan: your decision is written for the hook, which gives it to the session as Approve or Keep planning
    /// in the app would.
    func answerPlan(_ form: PendingForm, _ decision: PendingForm.PlanDecision, card: String) async -> Result<Void, Error> {
        if routerIsPretend { return Result { _ = try FormBridge.answerData(form, plan: decision) } }
        guard let dir = formBridge.dir else { return .failure(FormWriter.Cancelled()) }
        do {
            try await FormWriter.write(form, plan: decision, dir: dir) { [weak self] in
                guard let self else { return false }
                return self.routerOn && self.router.cards.first(where: { $0.id == card })?.isOpen == true
            }
            logCardAction(decision.approve ? "Approved the plan" : "Sent the plan back", card: card)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

/// Content redrawn on the minute and only then (ages, the status line): nothing else ticks for it.
struct MinuteTicking<Content: View>: View {
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(.everyMinute) { context in content(context.date) }
    }
}

// MARK: - Cards

extension RouterCard.Kind {
    var label: String {
        switch self {
        case .question: "Question"
        case .plan: "Plan"
        case .done: "Done"
        case .stuck: "Stuck"
        case .asks: "Asks you"
        case .approval: "Needs your OK"
        case .waiting: "Waiting"
        }
    }

    var color: Color {
        switch self {
        case .question: Theme.amber
        case .plan: Theme.purple
        case .done: Theme.accent
        case .stuck: Theme.red
        case .asks: Theme.amber
        case .approval: RouterTriage.approvalTint
        case .waiting: RouterTriage.waitingTint
        }
    }

    var symbol: String {
        switch self {
        case .question: "questionmark.bubble.fill"
        case .plan: "list.bullet.clipboard.fill"
        case .done: "checkmark"
        case .stuck: "exclamationmark.triangle.fill"
        case .asks: "bubble.left.and.text.bubble.right.fill"
        case .approval: "hand.raised.fill"
        case .waiting: "hourglass"
        }
    }
}

extension RouterCard.Addressed {
    /// What happened to an addressed card, in a few words.
    var label: String {
        switch self {
        case .you: "Marked addressed"
        case .reply: "You replied"
        case .router: "The Router passed it on"
        case .answered: "Answered"
        case .opened: "Opened"
        case .superseded: "Followed by a newer card"
        case .gone: "Session archived"
        }
    }
}

extension RouterCard {
    /// Whether it can be opened again (Reopen, Space): an addressed card, unless a newer card of its session replaced it or
    /// its session was archived or deleted.
    var canReopen: Bool { !isOpen && addressedBy != .superseded && addressedBy != .gone }
}

extension Store {
    /// `RouterCard.canReopen`, and once the app's sessions have been read, only while its session is still there and not
    /// archived: a card handled before its session went (only open cards are marked gone) isn't opened again on nothing.
    func routerCanReopen(_ card: RouterCard) -> Bool {
        guard card.canReopen else { return false }
        guard claudeLink == .ok else { return true }
        return claudeSessions[card.sessionID].map { !$0.isArchived } ?? false
    }
}

/// A card's kind in its colour: words and a glyph, never colour alone.
struct KindTag: View {
    let kind: RouterCard.Kind

    var body: some View {
        Label(kind.label, systemImage: kind.symbol)
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(kind.color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(kind.color.opacity(0.14)))
            .fixedSize()
    }
}

/// Card text is the app's own summary or the session's question: inline Markdown (**bold**, `code`) as the sessions show it.
enum RouterText {
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// A plan's Markdown, line by line as written: headings in bold without their #, the rest with its inline styles.
    static func plan(_ text: String) -> AttributedString {
        var out = AttributedString()
        for (i, raw) in text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() {
            if i > 0 { out += AttributedString("\n") }
            let line = String(raw)
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("#") {
                var heading = inline(String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                heading.inlinePresentationIntent = .stronglyEmphasized
                out += heading
            } else {
                out += inline(line)
            }
        }
        return out
    }
}

/// A card on two short lines, for the bar's panel: the session and its age, then the kind, the project and the text.
/// Clicking it opens its session in Claude (and picks it in the window).
struct RouterCardLine: View {
    let card: RouterCard
    let store: Store
    /// In a narrow column: the project goes (the kind and the text stay).
    var narrow = false
    let open: (String) -> Void
    @State private var hover = false

    var body: some View {
        let project = store.routerProject(card)
        Button { open(card.id) } label: {
            HStack(alignment: .top, spacing: 9) {
                if let session = store.sessionRow(card.sessionID) {
                    SessionGlyph(row: session, size: 18, dot: false).padding(.top, 1)
                } else {
                    Circle().fill(card.kind.color).frame(width: 6, height: 6).padding(.top, 6)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(card.title).font(Theme.Typography.bodyStrong).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(shortAgo(card.createdAt)).font(Theme.Typography.caption.monospacedDigit()).foregroundStyle(Theme.tertiary)
                    }
                    HStack(spacing: 6) {
                        KindTag(kind: card.kind)
                        if !narrow {
                            ProjectLabel(name: project.name, color: project.color)
                                .font(Theme.Typography.meta).foregroundStyle(Theme.tertiary).lineLimit(1).fixedSize()
                        }
                        Text(RouterText.inline(card.text)).font(Theme.Typography.meta).foregroundStyle(Theme.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowHighlight(hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu { if let session = store.sessionRow(card.sessionID) { SessionMenu(row: session, store: store) } }
        .accessibilityLabel("\(card.kind.label): \(card.title)")
        .accessibilityValue("\(project.name), \(card.text), \(AgentRow.spokenAge(Date().timeIntervalSince(card.createdAt))) ago")
        .accessibilityHint("Opens it in Claude")
    }
}

// MARK: - Window model

/// What the window remembers while it is closed (the draft, the picked card, the answers being put together), and what
/// the keys act on.
@Observable
@MainActor
final class RouterModel {
    /// The Working sessions' summaries being made.
    @ObservationIgnored let summarizer = RouterSummarizer()
    /// The card the keys act on.
    var selection: String?
    var draft = "" {
        didSet { if draft != oldValue { mentionChanged() } }
    }
    /// Asks the Router's conversation to scroll to a message (an inbox action's), selecting no card.
    var messageRequest: ScrollRequest?
    func show(message: UUID) {
        selection = nil
        messageRequest = ScrollRequest(id: message.uuidString, seq: (messageRequest?.seq ?? 0) + 1)
    }
    /// The card your next message answers: it goes to that card's session ("Replying to …" over the composer).
    var replyTo: String?
    /// Jev's pick for the draft while you type, and the target you fixed from it (see RouterJev.swift).
    let live = RouterLiveTarget()
    /// The pills in the draft (their projects' folders), one for each `MentionText.mark` in it, in order.
    var tokens: [String] = []
    /// Projects tagged with @ (their folders), in the order they stand in the draft: the Router looks there, and starts a
    /// session there.
    var projects: [String] {
        var seen = Set<String>()
        return tokens.filter { seen.insert($0).inserted }
    }
    /// While an @ is being typed: what follows it, and the suggestion picked with ↑↓.
    private(set) var mention: String?
    var mentionIndex = 0
    /// The @ word Esc dismissed: its suggestions stay away until it changes.
    @ObservationIgnored private var dismissedMention: String?
    /// Mirrors the composer's focus, for the keys.
    var composerFocused = false
    /// Bumped to ask the composer for the keyboard.
    var focusRequest = 0
    /// The keys that put the focus in the composer, typed into it once it has it.
    @ObservationIgnored var pendingKeys: [NSEvent] = []
    /// Per form (by its key): the options picked for each question, and the words typed in "Other".
    var picks: [String: [String: [String]]] = [:]
    var other: [String: [String: String]] = [:]
    /// Forms answered from here, until the session moves on, and what was sent.
    var sent: Set<String> = []
    var delivered: [String: [String: String]] = [:]
    /// Per plan (by its form's key): the note typed to go with "Keep planning", and what was decided from here.
    var planNotes: [String: String] = [:]
    var planDecided: [String: PendingForm.PlanDecision] = [:]

    /// The form's controls are shut while its answer is written and once it is.
    func locked(_ form: PendingForm) -> Bool { sending.contains(form.id) || sent.contains(form.id) }
    var formErrors: [String: String] = [:]

    /// Whether Claude Code was looked for and isn't there (see `checkClaudeCode`); nil until looked for.
    var claudeCodeMissing: Bool?
    /// Forms whose answer is being written.
    var sending: Set<String> = []
    /// The latest answer being written, for tests to wait on.
    @ObservationIgnored var lastWrite: Task<Void, Never>?
    /// The cards listed at the last reconcile, in order: where a picked card that left the list was.
    @ObservationIgnored private var listed: [String] = []

    /// The cards the keys walk, in the order the page shows them top to bottom: the addressed ones as the history above
    /// draws them (oldest first, the older ones it hasn't drawn yet before them); then what needs you (see
    /// `RouterPage.ranked`) and the finished turns, both open. Sessions waiting are with the working ones.
    func sections(_ store: Store) -> (needs: [RouterCard], done: [RouterCard], earlier: [RouterCard]) {
        // Only what the page shows: a finished turn whose session still runs things isn't there yet.
        let open = store.routerShownCards.filter { $0.isOpen && $0.kind != .waiting }.sorted(by: RouterPage.ranked)
        let byID = Dictionary(store.router.cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let earlier = store.routerHistory.compactMap { entry -> RouterCard? in
            guard case .card(let card) = entry, let now = byID[card.id], !now.isOpen else { return nil }
            return now
        }
        return (open.filter { $0.kind != .done }, open.filter { $0.kind == .done }, earlier)
    }

    /// Every card the keys walk, top to bottom.
    func cards(_ store: Store) -> [RouterCard] {
        let s = sections(store)
        return s.earlier + s.needs + s.done
    }

    /// Whether a message can go to the Router now: it is on (with the sessions extension) and Claude Code is there.
    func canSend(_ store: Store) -> Bool {
        store.routerOn && !(claudeCodeMissing == true && store.routerStatus.claudeCode == nil)
    }

    /// Looks for Claude Code once the window shows (the app updates its copy now and then): until the search has finished
    /// nothing is said, and Send waits. In a demo it is never missing.
    func checkClaudeCode(_ store: Store) async {
        if store.routerIsPretend || store.routerStatus.claudeCode != nil { claudeCodeMissing = false; return }
        guard let root = store.routerStatus.codeRoot else { claudeCodeMissing = false; return }
        let found = await Task.detached(priority: .utility) { RouterStatus.find(in: root) != nil }.value
        if claudeCodeMissing != !found { claudeCodeMissing = !found }
    }

    /// The pick follows the list: kept while it is listed; when the search or the cards change and it isn't, the nearest
    /// card listed after it (or before it) is picked, else none. Every key acts on the list as it is now.
    func reconcile(store: Store) {
        let ids = cards(store).map(\.id)
        defer { listed = ids }
        guard let id = selection, !ids.contains(id) else { return }
        let visible = Set(ids)
        var next: String?
        if let i = listed.firstIndex(of: id) {
            next = listed[(i + 1)...].first(where: visible.contains) ?? listed[..<i].reversed().first(where: visible.contains)
        }
        selection = next
    }

    /// Picks a card, or none (the Router itself), and takes the page there: an addressed card opens in the history, the
    /// Router row goes back down to the live zones. A card clicked is where you see it: the page is not taken anywhere.
    func select(_ id: String?, store: Store, reveal shows: Bool = true) {
        selection = id
        guard let id else { reveal(Self.endID, highlight: false); return }
        if let card = store.router.cards.first(where: { $0.id == id }) {
            // A session waiting is a row of Working.
            if card.isOpen, card.kind == .waiting { if shows { reveal(Self.workingID(card.sessionID)) }; return }
            if card.isOpen { expandedNeed = id } else { expanded.insert(id) }
        }
        if shows { reveal(id) }
    }

    /// What the page scrolls to for the bottom of the history, and the id of a working session's card.
    static let endID = "end"
    static func workingID(_ session: String) -> String { "working#" + session }

    /// Asks the page to scroll to an item (a card, a message, a working session's card) and, for a moment, to mark it.
    var revealRequest: ScrollRequest?
    /// The item marked for a moment after it was scrolled to.
    var highlighted: String?
    /// The card of Needs you shown in full (see `RouterPage.openNeed`); the others are summary rows.
    var expandedNeed: String?
    /// Addressed cards and runs opened out in the history.
    var expanded: Set<String> = []

    /// A history line (a run, a summary) opened out, or folded back.
    func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
    @ObservationIgnored private var highlightTask: Task<Void, Never>?

    func reveal(_ id: String, highlight: Bool = true) {
        revealRequest = ScrollRequest(id: id, seq: (revealRequest?.seq ?? 0) + 1)
        guard highlight else { return }
        highlighted = id
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            if !Task.isCancelled { self?.highlighted = nil }
        }
    }

    /// A card's Mark handled: it goes to the history at once (no timed undo: Reopen is there). The pick moves to the next
    /// open card if it was on this one.
    func address(_ id: String, store: Store) {
        reconcile(store: store)
        guard let card = store.router.cards.first(where: { $0.id == id }), card.isOpen else { return }
        let open = cards(store).filter(\.isOpen).map(\.id)
        let next = open.firstIndex(of: id).map { i in open.indices.contains(i + 1) ? open[i + 1] : i > 0 ? open[i - 1] : nil } ?? nil
        store.setCardAddressed(id, true)
        store.logCardAction("Marked handled", card: id)
        Announce.say("Addressed")
        if selection == id { selection = next }
    }

    /// Reopen on a history line: the card is back in Needs you and the page goes to it.
    func reopen(_ id: String, store: Store) {
        guard let card = store.router.cards.first(where: { $0.id == id }), store.routerCanReopen(card) else { return }
        store.setCardAddressed(id, false)
        expanded.remove(id)
        Announce.say("Open again")
        select(id, store: store)
    }

    /// ↑↓: the next card up or down the page. None picked, ↓ picks the first open card (the history is above it) and ↑ the
    /// last card.
    func move(down: Bool, store: Store) {
        reconcile(store: store)
        let shown = cards(store)
        guard !shown.isEmpty else { return }
        let ids = shown.map(\.id)
        guard let i = ids.firstIndex(of: selection ?? "") else {
            select(down ? (shown.first(where: \.isOpen) ?? shown[0]).id : ids[ids.count - 1], store: store)
            return
        }
        select(ids[min(max(i + (down ? 1 : -1), 0), ids.count - 1)], store: store)
    }

    /// Space: addressed, or open again. An addressed card goes up to the history, so the next open card is picked (or the one
    /// before it). A card superseded by a newer one of its session isn't opened again: the pick goes to that newer card; nor
    /// is one whose session is gone (`RouterCard.canReopen`, as Reopen).
    func toggleAddressed(store: Store) {
        reconcile(store: store)
        let shown = cards(store)
        guard let id = selection, let card = shown.first(where: { $0.id == id }) else { return }
        if !card.isOpen, !store.routerCanReopen(card) {
            if card.addressedBy == .superseded,
               let newer = store.routerShownOpenCards.first(where: { $0.sessionID == card.sessionID }) { select(newer.id, store: store) }
            return
        }
        let open = shown.filter(\.isOpen).map(\.id)
        let next = open.firstIndex(of: id).map { i in open.indices.contains(i + 1) ? open[i + 1] : i > 0 ? open[i - 1] : nil } ?? nil
        store.setCardAddressed(id, card.isOpen)
        if card.isOpen { store.logCardAction("Marked handled", card: id) }
        Announce.say(card.isOpen ? "Addressed" : "Open again")
        if card.isOpen { select(next, store: store) }
    }

    /// Sends the draft with its reply, its @pills (written as "@name" where they stand, their projects going with it) and the
    /// target you pinned; the composer keeps the focus for the next one.
    func send(store: Store) {
        let text = plainDraft(store)
        guard !text.isEmpty, canSend(store) else { return }
        store.sendToRouter(text, context: context(store))
        caret = nil
        tokens = []
        draft = ""
        replyTo = nil
        live.reset()
    }

    /// A card clicked: its session opens in Claude first (a finished turn is addressed by that, and goes up to the history),
    /// then the card is picked as it now is, so the pick stays on it.
    func open(_ id: String, store: Store) {
        store.openCard(id)
        select(id, store: store)
    }

    /// The composer takes the keyboard (typing anywhere in the window lands there).
    func reply() { focusRequest &+= 1 }

    /// Reply: a "Replying to" chip for that card over the composer, which takes the keyboard. Your words are yours to write.
    func reply(to card: String, store: Store, reveal: Bool = true) {
        select(card, store: store, reveal: reveal)
        replyTo = card
        focusRequest &+= 1
    }

    /// A card's header clicked: shown in full, with the composer ready to reply to it. A resolved card already shown in full
    /// folds back; the reply stays armed.
    func tap(_ id: String, store: Store) {
        let card = store.router.cards.first { $0.id == id }
        if let card, !card.isOpen, expanded.contains(id) {
            expanded.remove(id)
            return
        }
        reply(to: id, store: store, reveal: card?.isOpen != false)
    }

    // MARK: Chips and @

    /// Backspace at the start of the composer: the pinned target's chip goes, then the reply chip.
    @discardableResult
    func removeLastChip() -> Bool {
        if live.pinned != nil { live.reset(); return true }
        if replyTo != nil { replyTo = nil; return true }
        return false
    }

    /// The @ word being typed at the end of the draft, if any ("…@look" → "look").
    static func mentionQuery(in text: String, caret: Int? = nil) -> String? { mention(in: text, caret: caret)?.query }

    /// The @ word the caret is in or just after (`caret`: UTF-16 offset, nil for the end): its range (the whole word, past
    /// the caret too) and what is typed between the @ and the caret. An @ inside a word (an email) is not one.
    static func mention(in text: String, caret: Int?) -> (range: Range<String.Index>, query: String)? {
        if let caret, caret < 0 { return nil }
        let utf16 = text.utf16
        let offset = min(caret ?? utf16.count, utf16.count)
        guard let caretIndex = utf16.index(utf16.startIndex, offsetBy: offset, limitedBy: utf16.endIndex),
              let at = text[..<caretIndex].lastIndex(of: "@") else { return nil }
        if at != text.startIndex, !MentionText.isBreak(text[text.index(before: at)]) { return nil }
        let typed = text[text.index(after: at)..<caretIndex]
        guard !typed.contains(where: MentionText.isBreak) else { return nil }
        let end = text[caretIndex...].firstIndex(where: MentionText.isBreak) ?? text.endIndex
        return (at..<end, String(typed))
    }

    /// Where the caret is in the composer (UTF-16 offset; nil: at the end), as its text view says: the @ suggestions follow it.
    var caret: Int? {
        didSet { if caret != oldValue { mentionChanged() } }
    }
    /// Asks the composer to put its caret here (after a pick replaced the @ word).
    var caretRequest: Int?

    /// Takes the caret from the composer's text view; a selection (not a caret) shows no suggestions.
    func followCaret(_ editor: NSTextView) {
        let range = editor.selectedRange()
        let at = range.length == 0 ? range.location : -1
        let next: Int? = at == (draft as NSString).length ? nil : at
        if caret != next { caret = next }
    }

    private func mentionChanged() {
        let query = Self.mentionQuery(in: draft, caret: caret)
        if query != dismissedMention { dismissedMention = nil }
        let next = query == dismissedMention ? nil : query
        if next != mention {
            mention = next
            mentionIndex = 0
        }
    }

    /// The projects the @ word matches, best first (all of them for a bare @); the ones already tagged left out.
    func suggestions(_ store: Store) -> [(folder: String, name: String)] {
        guard let query = mention else { return [] }
        let folders = store.knownFolders.filter { !$0.isEmpty && !projects.contains($0) }
        return RouterMentions.rank(folders.map { ($0, store.folderName($0)) }, query: query, limit: 6)
    }

    /// Return or Tab on a suggestion: the @ word becomes that project's pill, in its place, with a space after it.
    func pickMention(_ folder: String) {
        guard mention != nil, let found = Self.mention(in: draft, caret: caret) else { return }
        let start = draft.utf16.distance(from: draft.utf16.startIndex, to: found.range.lowerBound.samePosition(in: draft.utf16)!)
        let before = draft[..<found.range.lowerBound].filter { $0 == MentionText.mark }.count
        let offset = draft.distance(from: draft.startIndex, to: found.range.lowerBound)
        var text = draft
        text.replaceSubrange(found.range, with: MentionText.markString)
        // One space after it, the one already there if any.
        let after = text.index(text.startIndex, offsetBy: offset + 1)
        let spaced = after < text.endIndex && text[after] == " "
        if !spaced { text.insert(" ", at: after) }
        var next = tokens
        next.insert(folder, at: min(before, next.count))
        caret = start + 2
        tokens = next
        draft = text
        caretRequest = start + 2
        mention = nil
    }

    /// Esc on the suggestions: they go until the @ word changes.
    func dismissMention() {
        dismissedMention = mention
        mention = nil
    }

    /// ↑↓ in the suggestions.
    func moveMention(down: Bool, count: Int) {
        guard count > 0 else { return }
        mentionIndex = (mentionIndex + (down ? 1 : count - 1)) % count
    }

    // MARK: Forms

    func picked(_ form: PendingForm, _ question: PendingForm.Question) -> [String] { picks[form.id]?[question.question] ?? [] }

    func otherText(_ form: PendingForm, _ question: PendingForm.Question) -> String { other[form.id]?[question.question] ?? "" }

    /// One choice picks it (and clears "Other"); several toggle.
    func pick(_ label: String, in question: PendingForm.Question, of form: PendingForm) {
        guard !locked(form) else { return }
        var current = picked(form, question)
        if question.multiSelect {
            if let i = current.firstIndex(of: label) { current.remove(at: i) } else { current.append(label) }
        } else {
            current = current == [label] ? [] : [label]
            other[form.id, default: [:]][question.question] = ""
        }
        picks[form.id, default: [:]][question.question] = current
        formErrors[form.id] = nil
    }

    /// Typing your own answer to a one-choice question unpicks the option.
    func setOther(_ text: String, in question: PendingForm.Question, of form: PendingForm) {
        guard !locked(form) else { return }
        other[form.id, default: [:]][question.question] = text
        if !question.multiSelect, !text.isEmpty { picks[form.id, default: [:]][question.question] = [] }
        formErrors[form.id] = nil
    }

    /// Every question's answer as the form takes it, or nil while one is missing.
    func answers(_ form: PendingForm) -> [String: String]? {
        var out: [String: String] = [:]
        for q in form.questions {
            let typed = otherText(form, q).trimmingCharacters(in: .whitespacesAndNewlines)
            let labels = picked(form, q) + (typed.isEmpty ? [] : [typed])
            guard !labels.isEmpty else { return nil }
            out[q.question] = q.multiSelect ? FormBridge.joined(labels) : labels[0]
        }
        return out
    }

    /// Lookout writes the answer itself (the hook passes it on to the session).
    /// The file is written off the main thread; "Sent" or the error shows once it is.
    func sendAnswer(_ form: PendingForm, card: String, store: Store) {
        guard let answers = answers(form), !sending.contains(form.id), !sent.contains(form.id) else { return }
        sending.insert(form.id)
        lastWrite = Task { [weak self] in
            let result = await store.answerForm(form, answers, card: card)
            guard let self else { return }
            self.sending.remove(form.id)
            switch result {
            case .success:
                self.sent.insert(form.id)
                self.delivered[form.id] = answers
                self.formErrors[form.id] = nil
                Announce.say("Answer sent")
            case .failure(let error):
                self.formErrors[form.id] = error.localizedDescription
                Announce.say("Couldn't send the answer: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Plans

    func planNote(_ form: PendingForm) -> String { planNotes[form.id] ?? "" }

    func setPlanNote(_ text: String, of form: PendingForm) {
        guard !locked(form) else { return }
        planNotes[form.id] = text
        formErrors[form.id] = nil
    }

    /// Approve, or Keep planning with the note if one is typed: written off the main thread like an answer, and passed on
    /// by the hook as the app's own buttons would.
    func decidePlan(_ form: PendingForm, approve: Bool, card: String, store: Store) {
        guard form.isPlan, !sending.contains(form.id), !sent.contains(form.id) else { return }
        let decision = PendingForm.PlanDecision(approve: approve, feedback: approve ? "" : planNote(form))
        sending.insert(form.id)
        lastWrite = Task { [weak self] in
            let result = await store.answerPlan(form, decision, card: card)
            guard let self else { return }
            self.sending.remove(form.id)
            switch result {
            case .success:
                self.sent.insert(form.id)
                self.planDecided[form.id] = decision
                self.formErrors[form.id] = nil
                Announce.say(approve ? "Plan approved" : "Sent back to keep planning")
            case .failure(let error):
                self.formErrors[form.id] = error.localizedDescription
                Announce.say("Couldn't send the decision: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Notice

/// What stands in the way of using the Router, in one line, and the fix. Nothing when all is well.
struct RouterSetupNotice: View {
    let store: Store
    let model: RouterModel

    var body: some View {
        Group {
            if !store.agents.enabled || !store.router.enabled {
                line("The Router is off.", color: Theme.amber, action: "Turn on") { store.switchRouter(true) }
            } else if model.claudeCodeMissing == true && store.routerStatus.claudeCode == nil {
                line("Claude Code wasn't found. Install or open the Claude desktop app.", color: Theme.amber,
                     action: "Look again") { Task { await model.checkClaudeCode(store) } }
            } else if let error = store.routerHookError {
                line("The form hook couldn't be installed: \(error)", color: Theme.red, action: nil) {}
            }
        }
    }

    private func line(_ text: String, color: Color, action: String?, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(color).accessibilityHidden(true)
                Text(text).font(Theme.Typography.meta).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let action { ActionButton(action, action: perform) }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.md)
            Hairline()
        }
        .onAppear { Announce.say(text) }
    }
}

/// The projects an @ word matches: names that start with it first, then ones that contain it, then ones that hold its
/// letters in order (fuzzy); shorter names first within each.
enum RouterMentions {
    static func rank(_ projects: [(String, String)], query: String, limit: Int) -> [(folder: String, name: String)] {
        let q = query.lowercased()
        func score(_ name: String) -> Int? {
            let n = name.lowercased()
            if q.isEmpty || n.hasPrefix(q) { return 0 }
            if n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) { return 1 }
            if n.contains(q) { return 2 }
            var rest = Substring(q)
            for c in n where c == rest.first { rest = rest.dropFirst() }
            return rest.isEmpty ? 3 : nil
        }
        struct Hit { var folder: String; var name: String; var score: Int }
        var hits: [Hit] = []
        for (folder, name) in projects {
            if let s = score(name) { hits.append(Hit(folder: folder, name: name, score: s)) }
        }
        hits.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            if a.name.count != b.name.count { return a.name.count < b.name.count }
            return a.name < b.name
        }
        return hits.prefix(limit).map { (folder: $0.folder, name: $0.name) }
    }
}

/// Router only: the sessions working now, under the Router's cards (the bar has no tiles to say so). One line each: the
/// project's colour, the title, what it is doing and for how long (on the minute); a click opens it in Claude.
struct RouterWorkingList: View {
    let store: Store
    /// Rows shown before the rest are counted.
    var limit = 5

    var body: some View {
        let rows = store.routerWorkingRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Eyebrow("Working", count: rows.count).padding(.horizontal, Theme.Space.md).padding(.top, 4).padding(.bottom, 2)
                MinuteTicking { now in
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(rows.prefix(limit)) { WorkingLine(row: $0, store: store, now: now) }
                    }
                }
                if rows.count > limit {
                    Text("\(rows.count - limit) more").font(Theme.Typography.meta).foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, Theme.Space.md)
                }
            }
        }
    }
}

private struct WorkingLine: View {
    let row: AgentRow
    let store: Store
    let now: Date
    @State private var hover = false

    /// How long, in whole minutes: the lists are redrawn once a minute, so seconds would only ever be wrong.
    private static func minutes(_ t: TimeInterval) -> String {
        let m = max(0, Int(t)) / 60
        if m < 1 { return "<1m" }
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    var body: some View {
        // A turn that is over but left things running: how many, since the oldest of them.
        let start = Store.workingStart(row)
        let since = Self.minutes(now.timeIntervalSince(start ?? now))
        let doing = row.session.running ? row.activity?.text ?? "Working" : row.tasksText ?? "Working"
        Button { store.openAgent(row.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SessionGlyph(row: row, size: 16, dot: false)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                Text(row.session.title).font(Theme.Typography.bodyMedium).foregroundStyle(Theme.text).lineLimit(1)
                    .layoutPriority(1)
                Text(doing).font(Theme.Typography.meta).foregroundStyle(row.session.running ? Theme.secondary : Theme.claude)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text(since).font(Theme.Typography.caption.monospacedDigit()).foregroundStyle(Theme.claude)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowHighlight(hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu { SessionMenu(row: row, store: store) }
        .runningTip(row.tasks)
        .accessibilityLabel(row.session.title)
        .accessibilityValue("working, \(row.projectName), \(doing), \(since)")
        .accessibilityHint("Opens it in Claude")
    }
}
