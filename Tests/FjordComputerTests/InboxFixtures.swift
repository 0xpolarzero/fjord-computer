import Foundation
@testable import FjordComputer

/// Things and a category for the inbox's tests: PRs of `a/one` that carry a Greptile score below 5 (the fact that puts them
/// in the category), so each is in "Mine" with the fact `Greptile 3/5`.
enum InboxFixture {
    static let author = Person(login: "me")

    static func category() -> InboxCategory {
        InboxCategory(name: "Mine", symbol: "star", color: .blue,
                      rules: [Rule(scope: Scope(kinds: [.pr]), conditions: [.greptileBelow(5)], createdAt: .distantPast)])
    }

    static func pr(_ n: Int, repo: String = "a/one", title: String = "t", by: Person = author, greptile: Int? = 3,
                   updated: Date = Date()) -> Thing {
        var thing = Thing(id: "pr:\(repo)#\(n)", kind: .pr, repo: repo, number: n, title: title,
                          url: URL(string: "https://github.com/\(repo)/pull/\(n)")!, author: by,
                          createdAt: updated.addingTimeInterval(-1000), updatedAt: updated)
        thing.greptileScore = greptile
        return thing
    }

    /// A category that asks GitHub for a repo's PRs, so a refresh has something to fetch.
    @MainActor static func watch(_ store: Store, _ repo: String = "a/one") {
        store.categories = [InboxCategory(name: "PRs", symbol: "star", color: .blue,
                                          rules: [Rule(scope: Scope(kinds: [.pr], in: Pick(include: [.repo(repo)])))])]
    }

    /// A store (saving nothing, Triage on) whose one category holds `things`.
    @MainActor static func store(_ things: [Thing], category: InboxCategory = category()) -> Store {
        let store = Store()
        store.persists = false
        store.settings.triage = true
        store.me = GHUser(login: "me", avatarUrl: nil, type: "User")
        store.categories = [category]
        store.things = Dictionary(uniqueKeysWithValues: things.map { ($0.id, $0) })
        return store
    }
}
