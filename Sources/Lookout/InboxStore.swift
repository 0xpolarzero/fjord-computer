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
        /// Each entry's search text, lowercased (see `Store.inboxRows`): made on the first search after a change.
        var searchKeys: [String: String]?

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
            inboxMemo = InboxStore.Memo(revision: inboxRevision, jev: context.jevSignals,
                                        expires: InboxEngine.nextChange(things: all, categories: categories, after: context.now),
                                        entries: result, marks: marks)
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
        if let keys = memo.searchKeys { return keys }
        let names = Dictionary(categories.map { ($0.id, $0.name.lowercased()) }, uniquingKeysWith: { first, _ in first })
        var keys: [String: String] = [:]
        keys.reserveCapacity(memo.entries.count)
        for entry in memo.entries {
            let t = entry.thing
            let key = "\(t.title) \(t.repo) #\(t.number ?? 0) @\(t.author?.login ?? "") \(t.workflowName ?? "") \(names[entry.categoryID] ?? "") "
                + entry.facts.map(\.label).joined(separator: " ")
            keys[entry.id] = key.lowercased()
        }
        inboxMemo.searchKeys = keys
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

    func moveCategory(from source: IndexSet, to destination: Int) { categories.move(fromOffsets: source, toOffset: destination) }

    /// Things the fetched cache has that `rule` matches: the editor's live preview.
    func preview(_ rule: Rule) -> [Thing] {
        InboxEngine.preview(rule, things: things.values, context: inboxContext)
    }
}
