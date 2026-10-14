import Foundation

// The Store's inbox: categories, groups, things fetched from GitHub, and what you did with them.
enum InboxStore {
    /// The inbox worked out once per `Store.inboxRevision`, which what it is made of bumps (things, marks, categories and
    /// their rules, groups, who you are, your repos and teams), and whether Jev's reading counts; the clock only as far as
    /// a rule on time passing (no activity for some days) goes: it holds until the next such threshold a thing crosses.
    /// What the window, the bar and the hub read on every redraw.
    struct Memo {
        var revision = -1
        /// Whether what Jev said counted (a setting, not an inbox change).
        var jev = true
        /// When time alone changes what matches: the next `no activity` threshold a thing crosses.
        var expires: Date?
        var entries: [InboxEntry] = []
        /// Each category's open entries, what Jev rates more important first (unrated counts as normal), then newest first.
        var open: [UUID: [InboxEntry]] = [:]
        /// How many of those are unread.
        var unread: [UUID: Int] = [:]
        /// Done entries, most recently done first.
        var done: [InboxEntry] = []
        /// Each entry's search text, lowercased (see `Store.inboxRows`): made on the first search after a change, as of
        /// `Store.inboxDisplayRevision` (it holds the categories' names).
        var searchKeys: (display: Int, keys: [String: String])?
        /// Waits for `expires`, then makes the change seen (`inboxTimePassed`) and announces what came in.
        var timer: Task<Void, Never>?

        init() {}

        /// Groups and sorts `entries` in one pass.
        init(revision: Int, jev: Bool, expires: Date?, entries: [InboxEntry], marks: [String: EntryMarks]) {
            self.revision = revision
            self.jev = jev
            self.expires = expires
            self.entries = entries
            var doneAt: [(Date, InboxEntry)] = []
            for entry in entries {
                if entry.isDone {
                    doneAt.append((marks[entry.id]?.doneAt ?? .distantPast, entry))
                } else {
                    open[entry.categoryID, default: []].append(entry)
                    if entry.isUnread { unread[entry.categoryID, default: 0] += 1 }
                }
            }
            func rank(_ e: InboxEntry) -> Int { (e.importance ?? .normal).rank }
            for id in open.keys {
                open[id]?.sort { rank($0) != rank($1) ? rank($0) > rank($1) : $0.thing.updatedAt > $1.thing.updatedAt }
            }
            done = doneAt.sorted { $0.0 > $1.0 }.map(\.1)
        }
    }

    /// Whether two lists of categories make the same inbox: the same categories in the same order, with the same rules,
    /// CI or not. What they are called and how they look, notify and act don't change what is in them.
    static func evaluatesAlike(_ a: [InboxCategory], _ b: [InboxCategory]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.id == $1.id && $0.isCI == $1.isCI && $0.rules == $1.rules }
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

    /// The inbox as of `inboxRevision` and whether Jev's reading counts, worked out again when either has moved or a thing
    /// has crossed a `no activity` threshold since.
    var inbox: InboxStore.Memo {
        if inboxMemo.revision != inboxRevision || inboxMemo.jev != jevReadsInbox
            || inboxMemo.expires.map({ Date() >= $0 }) == true {
            let context = inboxContext
            let all = Array(things.values)
            let result = InboxEngine.evaluate(things: all, categories: categories, marks: marks, context: context)
            var memo = InboxStore.Memo(revision: inboxRevision, jev: context.jevSignals,
                                       expires: InboxEngine.nextChange(things: all, categories: categories, after: context.now),
                                       entries: result, marks: marks)
            // One timer, for the next threshold: what shows the inbox and the notifications see it crossed, with no refresh.
            // None with Triage off (the Router may read the inbox, but nothing of it is announced or run).
            if inboxMemo.timer != nil, inboxMemo.expires == memo.expires {
                memo.timer = inboxMemo.timer
            } else {
                inboxMemo.timer?.cancel()
                if let expires = memo.expires, triageOn {
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
        }
        return inboxMemo
    }

    /// Every entry, memoized (see `inbox`).
    var entries: [InboxEntry] { inbox.entries }

    /// Open entries of a category, what Jev rates more important first (unrated counts as normal), then newest first.
    func entries(in category: UUID) -> [InboxEntry] { inbox.open[category] ?? [] }

    /// Done entries, most recently done first.
    var doneEntries: [InboxEntry] { inbox.done }

    /// The bar's number for a category: its open entries.
    func count(_ category: UUID) -> Int { entries(in: category).count }
    func unreadCount(_ category: UUID) -> Int { inbox.unread[category] ?? 0 }

    /// Each entry's search text, lowercased, by entry id: made once per `inboxRevision`, on the first search.
    var inboxSearchKeys: [String: String] {
        let memo = inbox
        let display = inboxDisplayRevision
        if let kept = memo.searchKeys, kept.display == display { return kept.keys }
        let names = Dictionary(categories.map { ($0.id, $0.name.lowercased()) }, uniquingKeysWith: { first, _ in first })
        var keys: [String: String] = [:]
        keys.reserveCapacity(memo.entries.count)
        for entry in memo.entries {
            let t = entry.thing
            let key = "\(t.title) \(t.repo) #\(t.number ?? 0) @\(t.author?.login ?? "") \(t.workflowName ?? "") \(names[entry.categoryID] ?? "") "
                + entry.facts.map(\.label).joined(separator: " ")
            keys[entry.id] = key.lowercased()
        }
        inboxMemo.searchKeys = (display, keys)
        return keys
    }

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

    /// How many of a category's rules are off (a chip that can never match, a group gone), as the engine keeps them.
    /// Worked out for every category at once, once per `inboxRevision` (which rules and groups changing move), not per
    /// call: rows and tabs ask in every body. The inbox itself isn't worked out for it.
    func rulesOff(_ id: UUID) -> Int {
        let revision = inboxRevision
        if let memo = rulesOffMemo, memo.revision == revision { return memo.counts[id] ?? 0 }
        var counts: [UUID: Int] = [:]
        for category in categories {
            counts[category.id] = category.rules.filter { !InboxEngine.problems($0, in: category, groups: groups).isEmpty }.count
        }
        rulesOffMemo = (revision, counts)
        return counts[id] ?? 0
    }

    /// Opens the category's editor: the categories page takes the request when it shows (`go` takes the window there).
    func editCategory(_ id: UUID, go: (AppDestination) -> Void) {
        categoryEditorRequest = id
        go(.categories)
    }

    /// Opens the editor of a new category: the categories page takes the request when it shows (`go` takes the window there).
    func newCategory(go: (AppDestination) -> Void) {
        newCategoryRequest = true
        go(.categories)
    }

    func moveCategory(from source: IndexSet, to destination: Int) { categories.move(fromOffsets: source, toOffset: destination) }

    /// Your assignment rated (and marked, and acted on) before GitHub said when it was made, as `assigned`, is the same
    /// assignment once its time is known (`assigned:<t>`): its rating, its facts' marks (seen, Done, notified) and its
    /// actions' records are carried over to that stamp, once, rather than it coming in again as new. Called as things change,
    /// with `seenBefore` the things as they were: only an assignment already there when the thing was last seen is the same
    /// one (its time as seen then, or, seen without a time, made no later than the thing's last update then). One made since
    /// (taken off and assigned again while the app was closed) is new: what was said of the old one is dropped, not carried.
    func carryAssignmentStamps(seenBefore: [String: Thing]) {
        let legacy = ":assigned"
        func isLegacy(_ key: String) -> Bool { key.hasPrefix("importance:") && key.hasSuffix(legacy) }
        let candidates = things.values.filter { thing in
            thing.assignedAt != nil && (thing.signals?.importance?.stamp == "assigned"
                || marks[thing.id].map { m in (m.seen.union(m.acked).union(m.notified)).contains(where: isLegacy) } ?? false)
        }
        guard !candidates.isEmpty else { return }
        let context = inboxContext
        let me = InboxEngine.viewer(context.me)
        // By thing: the stamp's suffix it is carried to, or nil where it is dropped.
        var carried: [String: String?] = [:]
        var updated = things, newMarks = marks
        for thing in candidates {
            guard let stamp = InboxEngine.importanceStamp(thing, context: context), stamp.hasPrefix("assigned:"),
                  let at = Int(stamp.dropFirst("assigned:".count)) else { continue }
            let before = seenBefore[thing.id]
            let wasMine = before?.assignees.contains { InboxEngine.viewer($0) == me } ?? false
            let seenAt = before?.assignedAt?.first { InboxEngine.viewer($0.key) == me }?.value
            let same = wasMine
                && (seenAt.map { Int($0.timeIntervalSince1970) == at } ?? (at <= Int(before!.updatedAt.timeIntervalSince1970)))
            let suffix: String? = same ? String(stamp.dropFirst("assigned".count)) : nil
            func carry(_ key: String) -> String? { isLegacy(key) ? suffix.map { key + $0 } : key }
            carried[thing.id] = .some(suffix)
            if thing.signals?.importance?.stamp == "assigned" {
                if same { updated[thing.id]?.signals?.importance?.stamp = stamp } else { updated[thing.id]?.signals?.importance = nil }
            }
            if var m = newMarks[thing.id] {
                m.seen = Set(m.seen.compactMap(carry))
                m.acked = Set(m.acked.compactMap(carry))
                m.notified = Set(m.notified.compactMap(carry))
                m.doneFacts = m.doneFacts?.compactMap { f in carry(f.key).map { var f = f; f.key = $0; return f } }
                if m.doneFacts?.isEmpty == true { m.doneFacts = nil }
                newMarks[thing.id] = m
            }
        }
        guard !carried.isEmpty else { return }
        var ledger = actionLedger
        for (key, run) in ledger.runs where isLegacy(run.trigger) {
            guard let suffix = carried[run.thing] else { continue }
            ledger.runs[key] = nil
            guard let suffix else { continue }
            var moved = run
            moved.trigger += suffix
            if ledger.run(moved.category, moved.thing, moved.action, moved.trigger) == nil { ledger.set(moved) }
        }
        // Things last: setting them calls this again, which then finds nothing left to carry.
        if newMarks != marks { marks = newMarks }
        if ledger != actionLedger { actionLedger = ledger }
        if updated != things { things = updated }
    }

    /// Things the fetched cache has that `rule` matches: the editor's live preview.
    func preview(_ rule: Rule) -> [Thing] {
        InboxEngine.preview(rule, things: things.values, context: inboxContext)
    }
}
