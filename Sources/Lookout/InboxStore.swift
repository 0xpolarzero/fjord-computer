import Foundation

// The Store's inbox: categories, groups, things fetched from GitHub, and what you did with them.
enum InboxStore {
    struct Memo {
        var revision = -1
        /// Whether what Jev said counted (a setting, not an inbox change).
        var jev = true
        var entries: [InboxEntry] = []
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

    /// Every entry, memoized on `inboxRevision` and whether Jev's reading counts.
    var entries: [InboxEntry] {
        if inboxMemo.revision == inboxRevision, inboxMemo.jev == jevReadsInbox { return inboxMemo.entries }
        let context = inboxContext
        let result = InboxEngine.evaluate(things: Array(things.values), categories: categories, marks: marks, context: context)
        inboxMemo = InboxStore.Memo(revision: inboxRevision, jev: context.jevSignals, entries: result)
        return result
    }

    /// Open entries of a category, what Jev rates more important first (unrated counts as normal), then newest first.
    func entries(in category: UUID) -> [InboxEntry] {
        func rank(_ e: InboxEntry) -> Int { (e.importance ?? .normal).rank }
        return entries.filter { $0.categoryID == category && !$0.isDone }.sorted {
            rank($0) != rank($1) ? rank($0) > rank($1) : $0.thing.updatedAt > $1.thing.updatedAt
        }
    }

    /// Done entries, most recently done first.
    var doneEntries: [InboxEntry] {
        entries.filter(\.isDone).sorted { (marks[$0.id]?.doneAt ?? .distantPast) > (marks[$1.id]?.doneAt ?? .distantPast) }
    }

    /// The bar's number for a category: its open entries.
    func count(_ category: UUID) -> Int { entries(in: category).count }
    func unreadCount(_ category: UUID) -> Int { entries(in: category).filter(\.isUnread).count }

    func markDone(_ entry: InboxEntry) {
        var m = marks[entry.id] ?? EntryMarks()
        m.acked.formUnion(entry.facts.map(\.key))
        m.seen.formUnion(entry.facts.map(\.key))
        m.doneAt = Date()
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
        marks[entry.id] = m
    }

    func moveCategory(from source: IndexSet, to destination: Int) { categories.move(fromOffsets: source, toOffset: destination) }

    /// Things the fetched cache has that `rule` matches: the editor's live preview.
    func preview(_ rule: Rule) -> [Thing] {
        let context = inboxContext
        return things.values.filter { InboxEngine.facts(rule, $0, marks: nil, context: context) != nil }
    }
}
