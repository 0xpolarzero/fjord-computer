import Foundation

// The Store's inbox: categories, groups, things fetched from GitHub, and what you did with them.
enum InboxStore {
    struct Memo {
        var revision = -1
        var entries: [InboxEntry] = []
    }

    /// Done is always there and isn't a category; CI is the one default.
    static let defaultCategories: [InboxCategory] = [
        InboxCategory(name: "CI", symbol: "xmark.seal", color: .red,
                      rules: [Rule(scope: Scope(kinds: [.workflow], in: Pick()), conditions: [.workflow([.failing])])],
                      isCI: true),
    ]
}

extension Store {
    var inboxContext: InboxContext {
        InboxContext(me: me?.login ?? "", groups: groups, ownedRepos: ownedRepos, contributedRepos: contributedRepos,
                      myTeams: myTeams)
    }

    /// Every entry, memoized on `inboxRevision`.
    var entries: [InboxEntry] {
        if inboxMemo.revision == inboxRevision { return inboxMemo.entries }
        let result = InboxEngine.evaluate(things: Array(things.values), categories: categories, marks: marks,
                                          context: inboxContext)
        inboxMemo = InboxStore.Memo(revision: inboxRevision, entries: result)
        return result
    }

    /// Open entries of a category, newest first.
    func entries(in category: UUID) -> [InboxEntry] {
        entries.filter { $0.categoryID == category && !$0.isDone }.sorted { $0.thing.updatedAt > $1.thing.updatedAt }
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
