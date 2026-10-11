import Foundation

// The Store's inbox: categories, groups, things fetched from GitHub, and what you did with them.
enum InboxStore {
    struct Memo {
        var revision = -1
        /// Whether what Jev said counted (a setting, not an inbox change).
        var jev = true
        /// When time alone changes what matches: the next `no activity` threshold a thing crosses.
        var expires: Date?
        var entries: [InboxEntry] = []
        /// Each category's open entries in the order they show, its unread count, and Done's entries: what the bar and the
        /// lists read on every redraw, grouped once with `entries`.
        var open: [UUID: [InboxEntry]] = [:]
        var unread: [UUID: Int] = [:]
        var done: [InboxEntry] = []
        /// Waits for `expires`, then makes the change seen (`inboxTimePassed`) and announces what came in.
        var timer: Task<Void, Never>?
    }

    /// Done is always there and isn't a category. A new inbox starts with My repos: the PRs and issues in the repos you own.
    static let defaultCategories: [InboxCategory] = [myRepos]

    /// The CI category: failing workflows, counted as failures. Not a default; deleting it is like deleting any other.
    static let ci = InboxCategory(name: "CI", symbol: "xmark.seal", color: .red,
                                  rules: [Rule(scope: Scope(kinds: [.workflow], in: Pick()), conditions: [.workflow([.failing])])],
                                  isCI: true)
    static let myRepos = InboxCategory(name: "My repos", symbol: "folder", color: .blue,
                                       rules: [Rule(scope: Scope(kinds: [.pr, .issue], in: Pick(include: [.owned])))], notifies: false)
}

extension Store {
    var inboxContext: InboxContext {
        InboxContext(me: me?.login ?? login, groups: groups, contributedRepos: contributedRepos,
                      myTeams: myTeams, jevSignals: jevReadsInbox)
    }

    /// Every entry, memoized on `inboxRevision` and whether Jev's reading counts, until a thing crosses a `no activity`
    /// threshold.
    var entries: [InboxEntry] { inboxEvaluated.entries }

    /// The memo, evaluated again when it is out of date.
    private var inboxEvaluated: InboxStore.Memo {
        if inboxMemo.revision == inboxRevision, inboxMemo.jev == jevReadsInbox, inboxMemo.expires.map({ Date() < $0 }) ?? true {
            return inboxMemo
        }
        let context = inboxContext
        let all = Array(things.values)
        let result = InboxEngine.evaluate(things: all, categories: categories, marks: marks, context: context)
        var memo = InboxStore.Memo(revision: inboxRevision, jev: context.jevSignals,
                                   expires: InboxEngine.nextChange(things: all, categories: categories, after: context.now),
                                   entries: result)
        // Open: what Jev rates more important first (unrated counts as normal), then newest first. Done: most recently done first.
        func rank(_ e: InboxEntry) -> Int { (e.importance ?? .normal).rank }
        memo.open = Dictionary(grouping: result.filter { !$0.isDone }, by: \.categoryID).mapValues {
            $0.sorted { rank($0) != rank($1) ? rank($0) > rank($1) : $0.thing.updatedAt > $1.thing.updatedAt }
        }
        memo.unread = memo.open.mapValues { $0.filter(\.isUnread).count }
        memo.done = result.filter(\.isDone).sorted { (marks[$0.id]?.doneAt ?? .distantPast) > (marks[$1.id]?.doneAt ?? .distantPast) }
        // One timer, for the next threshold: what shows the inbox and the notifications see it crossed, with no refresh.
        if inboxMemo.timer != nil, inboxMemo.expires == memo.expires {
            memo.timer = inboxMemo.timer
        } else {
            inboxMemo.timer?.cancel()
            if let expires = memo.expires {
                memo.timer = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(max(0, expires.timeIntervalSinceNow) + 0.05))
                    guard !Task.isCancelled, let self else { return }
                    inboxMemo.timer = nil
                    inboxTimePassed()
                    announceInbox()
                }
            }
        }
        inboxMemo = memo
        return memo
    }

    /// Open entries of a category, what Jev rates more important first (unrated counts as normal), then newest first.
    func entries(in category: UUID) -> [InboxEntry] { inboxEvaluated.open[category] ?? [] }

    /// Done entries, most recently done first.
    var doneEntries: [InboxEntry] { inboxEvaluated.done }

    /// The bar's number for a category: its open entries.
    func count(_ category: UUID) -> Int { entries(in: category).count }
    func unreadCount(_ category: UUID) -> Int { inboxEvaluated.unread[category] ?? 0 }

    func markDone(_ entry: InboxEntry) {
        var m = marks[entry.id] ?? EntryMarks()
        m.acked.formUnion(entry.facts.map(\.key))
        m.seen.formUnion(entry.facts.map(\.key))
        m.doneAt = Date()
        m.doneIn = entry.categoryID
        m.doneFacts = entry.facts
        marks[entry.id] = m
    }

    func markSeen(_ entry: InboxEntry) {
        var m = marks[entry.id] ?? EntryMarks()
        m.seen.formUnion(entry.facts.map(\.key))
        marks[entry.id] = m
    }

    /// Unread again: what it says now counts as not seen (it isn't notified again).
    func markUnread(_ entry: InboxEntry) {
        guard var m = marks[entry.id] else { return }
        m.seen.subtract(entry.facts.map(\.key))
        marks[entry.id] = m
    }

    func restore(_ entry: InboxEntry) {
        var m = marks[entry.id] ?? EntryMarks()
        m.acked.subtract(entry.facts.map(\.key))
        m.doneAt = nil
        m.doneIn = nil
        m.doneFacts = nil
        marks[entry.id] = m
    }

    func moveCategory(from source: IndexSet, to destination: Int) { categories.move(fromOffsets: source, toOffset: destination) }

    /// Your assignment rated (and marked, and acted on) before GitHub said when it was made, as `assigned`, is the same
    /// assignment once its time is known (`assigned:<t>`): its rating, its facts' marks (seen, Done, notified) and its
    /// actions' records are carried over to that stamp, once, rather than it coming in again as new. Called as things change.
    func carryAssignmentStamps() {
        let legacy = ":assigned"
        func isLegacy(_ key: String) -> Bool { key.hasPrefix("importance:") && key.hasSuffix(legacy) }
        let candidates = things.values.filter { thing in
            thing.assignedAt != nil && (thing.signals?.importance?.stamp == "assigned"
                || marks[thing.id].map { m in (m.seen.union(m.acked).union(m.notified)).contains(where: isLegacy) } ?? false)
        }
        guard !candidates.isEmpty else { return }
        let context = inboxContext
        var carried: [String: String] = [:]
        var updated = things, newMarks = marks
        for thing in candidates {
            guard let stamp = InboxEngine.importanceStamp(thing, context: context), stamp.hasPrefix("assigned:") else { continue }
            let suffix = String(stamp.dropFirst("assigned".count))
            func carry(_ key: String) -> String { isLegacy(key) ? key + suffix : key }
            carried[thing.id] = suffix
            if thing.signals?.importance?.stamp == "assigned" { updated[thing.id]?.signals?.importance?.stamp = stamp }
            if var m = newMarks[thing.id] {
                m.seen = Set(m.seen.map(carry))
                m.acked = Set(m.acked.map(carry))
                m.notified = Set(m.notified.map(carry))
                m.doneFacts = m.doneFacts?.map { var f = $0; f.key = carry(f.key); return f }
                newMarks[thing.id] = m
            }
        }
        guard !carried.isEmpty else { return }
        var ledger = actionLedger
        for (key, run) in ledger.runs where isLegacy(run.trigger) {
            guard let suffix = carried[run.thing] else { continue }
            var moved = run
            moved.trigger += suffix
            ledger.runs[key] = nil
            if ledger.run(moved.category, moved.thing, moved.action, moved.trigger) == nil { ledger.set(moved) }
        }
        if updated != things { things = updated }
        if newMarks != marks { marks = newMarks }
        if ledger != actionLedger { actionLedger = ledger }
    }

    /// Things the fetched cache has that `rule` matches: the editor's live preview.
    func preview(_ rule: Rule) -> [Thing] {
        let context = inboxContext
        return things.values.filter { InboxEngine.facts(rule, $0, marks: nil, context: context) != nil }
    }
}
