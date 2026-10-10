import Foundation
import SwiftUI

// The inbox as categories of things (PRs, issues, workflows) and the facts that put them there.
// A category is rules; a rule is a scope (which things) and conditions (when they need you). Every condition is a
// literal fact one could check on GitHub. A thing is in the first category, top to bottom, that one of its rules
// matches; unmatched things are dropped. Done is not a category: it is the things whose current facts you acknowledged.

// MARK: - Values

enum ThingKind: String, Codable, CaseIterable, Hashable {
    case pr, issue, workflow

    var label: String {
        switch self {
        case .pr: "PRs"
        case .issue: "Issues"
        case .workflow: "Workflows"
        }
    }
}

extension Set where Element == ThingKind {
    /// In the kinds' order: "PRs", "PRs and issues".
    var label: String {
        let words = ThingKind.allCases.filter(contains).enumerated().map { $0 == 0 ? $1.label : $1.label.lowercased() }
        guard let last = words.last else { return "Nothing" }
        return words.count == 1 ? last : words.dropLast().joined(separator: ", ") + " and " + last
    }
}

/// Someone a slot names.
enum PersonRef: Codable, Hashable {
    case me
    case user(String)
    case group(UUID)
    /// GitHub's role on the thing's repo: owner, member or collaborator.
    case maintainers
    /// Accounts GitHub marks as bots.
    case bots
    /// A team asked to review: `org/team` (shown `@org/team`). Only means something in `to`.
    case team(String)
    /// Every team you're in (resolved daily). Only means something in `to`.
    case myTeams
}

/// Somewhere a slot names.
enum RepoRef: Codable, Hashable {
    case repo(String)
    /// Every repo of an owner: `owner/*`.
    case owner(String)
    case group(UUID)
    case owned
    /// Repos with a merged or open PR of yours.
    case contributed
    /// PRs and issues only: you're the author, assignee or requested reviewer, were mentioned, or commented.
    case involved
}

/// A slot's values. Empty `include` means anyone/anywhere (only meaningful with `except`).
struct Pick<Value: Codable & Hashable>: Codable, Hashable {
    var include: [Value] = []
    var except: [Value] = []
}

/// What "to" covers; the word itself is a menu narrowing it.
enum ToRole: String, Codable, CaseIterable, Hashable {
    case assigned, reviewRequested, mentioned
}

/// Which things a rule is about. A nil slot was not added: it means any and isn't shown.
struct Scope: Hashable {
    /// At least one. PRs and issues share a rule; workflows are a rule of their own: they have no author and no `to`, need
    /// repos, and have branches and names nothing else has, so a rule mixing them would have no slots that fit it all.
    var kinds: Set<ThingKind>
    var by: Pick<PersonRef>?
    var to: Pick<PersonRef>?
    var toRoles: Set<ToRole> = Set(ToRole.allCases)
    /// Required for workflows.
    var `in`: Pick<RepoRef>?
    /// Workflows: branches; nil is the repo's default branch.
    var on: [String]?
    /// Workflows: names; nil is every workflow.
    var named: [String]?

    init(kinds: Set<ThingKind>, by: Pick<PersonRef>? = nil, to: Pick<PersonRef>? = nil, toRoles: Set<ToRole> = Set(ToRole.allCases),
         in repos: Pick<RepoRef>? = nil, on: [String]? = nil, named: [String]? = nil) {
        self.kinds = kinds
        self.by = by
        self.to = to
        self.toRoles = toRoles
        self.in = repos
        self.on = on
        self.named = named
    }

    /// A workflow rule: repos, branches and names rather than people.
    var isWorkflow: Bool { kinds.contains(.workflow) }
}

extension Scope: Codable {
    private enum CodingKeys: String, CodingKey { case kinds, kind, by, to, toRoles, `in`, on, named }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Rules saved before a rule could be about more than one kind have `kind`, one value.
        kinds = try c.decodeIfPresent(Set<ThingKind>.self, forKey: .kinds) ?? [c.decode(ThingKind.self, forKey: .kind)]
        by = try c.decodeIfPresent(Pick<PersonRef>.self, forKey: .by)
        to = try c.decodeIfPresent(Pick<PersonRef>.self, forKey: .to)
        toRoles = try c.decodeIfPresent(Set<ToRole>.self, forKey: .toRoles) ?? Set(ToRole.allCases)
        self.in = try c.decodeIfPresent(Pick<RepoRef>.self, forKey: .in)
        on = try c.decodeIfPresent([String].self, forKey: .on)
        named = try c.decodeIfPresent([String].self, forKey: .named)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // In the kinds' order, so the same rule is always the same JSON.
        try c.encode(ThingKind.allCases.filter(kinds.contains), forKey: .kinds)
        try c.encodeIfPresent(by, forKey: .by)
        try c.encodeIfPresent(to, forKey: .to)
        try c.encode(ToRole.allCases.filter(toRoles.contains), forKey: .toRoles)
        try c.encodeIfPresent(self.in, forKey: .in)
        try c.encodeIfPresent(on, forKey: .on)
        try c.encodeIfPresent(named, forKey: .named)
    }
}

enum CheckState: String, Codable, CaseIterable, Hashable {
    case failing, pending, passing
}

enum ThingStatus: String, Codable, CaseIterable, Hashable {
    case open, draft, merged, closed
}

/// What an activity condition counts events after.
enum Since: String, Codable, CaseIterable, Hashable {
    /// Since you last marked the thing done (or the rule was made): the default.
    case done
    /// After your latest review on the thing; with none, nothing matches.
    case myLastReview
    /// After your latest comment on the thing (a conversation comment, a review with text, a thread reply); with none,
    /// since the thing was created.
    case myLastComment
}

/// A fact a rule asks for. Activity conditions are events since a point (`Since`, by default you last marked the thing
/// done); the others are true or not right now.
enum Condition: Codable, Hashable {
    // Activity
    case newComment(by: Pick<PersonRef>, since: Since = .done)
    case newReview(by: Pick<PersonRef>, since: Since = .done)
    case newCommits(by: Pick<PersonRef>, since: Since = .done)
    case mentions(Pick<PersonRef>, since: Since = .done)
    // Conversation
    /// The latest Conversation-tab comment (reviews with text count, inline threads don't).
    case lastComment(by: Pick<PersonRef>)
    /// Open threads: unresolved and, when given, started by / last replied to by.
    case unresolvedThreads(startedBy: Pick<PersonRef>?, lastReplyBy: Pick<PersonRef>?)
    // Review, from each reviewer's latest review
    case approved(by: Pick<PersonRef>)
    case changesRequested(by: Pick<PersonRef>)
    // Checks
    case checks(Set<CheckState>)
    case hasConflicts
    /// The base branch has moved on (GitHub's mergeStateStatus BEHIND; only reported when the base branch's protection
    /// requires branches to be up to date).
    case behindBase
    // Status
    /// PRs/issues: draft, ready (= open and not draft), merged, closed. `.open` here means ready for review.
    case status(Set<ThingStatus>)
    case labeled(Pick<String>)
    case noActivity(days: Int)
    // Signals
    case greptileBelow(Int)
    /// Jev read a comment, review or thread reply (not yours) since you last answered there or marked it done, and it asks
    /// you something.
    case asksMe
    /// A new comment (not yours) is noise (`true`: bots, and what Jev reads as automated) or from a person (`false`).
    case noise(Bool)
    /// Jev rates the review request or assignment at least this important.
    case importance(Importance)
    // Workflows
    case workflow(Set<CheckState>)
}

/// How much a review request or an assignment matters, as Jev rates it (InboxJev.swift).
enum Importance: String, Codable, CaseIterable, Comparable, Hashable {
    case low, normal, high, urgent

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (a: Importance, b: Importance) -> Bool { a.rank < b.rank }
}

// Rules saved before `since` have no such key: the activity cases are read by hand, the rest as they always were.
extension Condition {
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private enum ActivityKey: String, CodingKey { case by, _0, since }

    private enum Activity: String { case newComment, newReview, newCommits, mentions }

    /// Every case but the activity ones, encoded the way the synthesized coding always did.
    private enum Other: Codable {
        case lastComment(by: Pick<PersonRef>)
        case unresolvedThreads(startedBy: Pick<PersonRef>?, lastReplyBy: Pick<PersonRef>?)
        case approved(by: Pick<PersonRef>)
        case changesRequested(by: Pick<PersonRef>)
        case checks(Set<CheckState>)
        case hasConflicts
        case behindBase
        case status(Set<ThingStatus>)
        case labeled(Pick<String>)
        case noActivity(days: Int)
        case greptileBelow(Int)
        case asksMe
        case noise(Bool)
        case importance(Importance)
        case workflow(Set<CheckState>)

        init?(_ c: Condition) {
            switch c {
            case .newComment, .newReview, .newCommits, .mentions: return nil
            case .lastComment(let by): self = .lastComment(by: by)
            case .unresolvedThreads(let a, let b): self = .unresolvedThreads(startedBy: a, lastReplyBy: b)
            case .approved(let by): self = .approved(by: by)
            case .changesRequested(let by): self = .changesRequested(by: by)
            case .checks(let s): self = .checks(s)
            case .hasConflicts: self = .hasConflicts
            case .behindBase: self = .behindBase
            case .status(let s): self = .status(s)
            case .labeled(let p): self = .labeled(p)
            case .noActivity(let d): self = .noActivity(days: d)
            case .greptileBelow(let n): self = .greptileBelow(n)
            case .asksMe: self = .asksMe
            case .noise(let b): self = .noise(b)
            case .importance(let i): self = .importance(i)
            case .workflow(let s): self = .workflow(s)
            }
        }

        var condition: Condition {
            switch self {
            case .lastComment(let by): .lastComment(by: by)
            case .unresolvedThreads(let a, let b): .unresolvedThreads(startedBy: a, lastReplyBy: b)
            case .approved(let by): .approved(by: by)
            case .changesRequested(let by): .changesRequested(by: by)
            case .checks(let s): .checks(s)
            case .hasConflicts: .hasConflicts
            case .behindBase: .behindBase
            case .status(let s): .status(s)
            case .labeled(let p): .labeled(p)
            case .noActivity(let d): .noActivity(days: d)
            case .greptileBelow(let n): .greptileBelow(n)
            case .asksMe: .asksMe
            case .noise(let b): .noise(b)
            case .importance(let i): .importance(i)
            case .workflow(let s): .workflow(s)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let top = try decoder.container(keyedBy: AnyKey.self)
        guard let key = top.allKeys.first, let kind = Activity(rawValue: key.stringValue) else {
            self = try Other(from: decoder).condition
            return
        }
        let c = try top.nestedContainer(keyedBy: ActivityKey.self, forKey: key)
        // `by` for the labeled cases, `_0` for mentions.
        let pick = try c.decodeIfPresent(Pick<PersonRef>.self, forKey: .by) ?? c.decode(Pick<PersonRef>.self, forKey: ._0)
        let since = try c.decodeIfPresent(Since.self, forKey: .since) ?? .done
        switch kind {
        case .newComment: self = .newComment(by: pick, since: since)
        case .newReview: self = .newReview(by: pick, since: since)
        case .newCommits: self = .newCommits(by: pick, since: since)
        case .mentions: self = .mentions(pick, since: since)
        }
    }

    func encode(to encoder: Encoder) throws {
        let name: String, pick: Pick<PersonRef>, since: Since
        let labeled: Bool
        switch self {
        case .newComment(let p, let s): (name, pick, since, labeled) = ("newComment", p, s, true)
        case .newReview(let p, let s): (name, pick, since, labeled) = ("newReview", p, s, true)
        case .newCommits(let p, let s): (name, pick, since, labeled) = ("newCommits", p, s, true)
        case .mentions(let p, let s): (name, pick, since, labeled) = ("mentions", p, s, false)
        default:
            try Other(self)?.encode(to: encoder)
            return
        }
        var top = encoder.container(keyedBy: AnyKey.self)
        var c = top.nestedContainer(keyedBy: ActivityKey.self, forKey: AnyKey(stringValue: name)!)
        try c.encode(pick, forKey: labeled ? .by : ._0)
        if since != .done { try c.encode(since, forKey: .since) }
    }
}

enum MatchMode: String, Codable, Hashable {
    case any, all
}

struct Rule: Codable, Hashable, Identifiable {
    var id = UUID()
    var scope: Scope
    var match: MatchMode = .any
    /// Empty: every open thing in scope.
    var conditions: [Condition] = []
    /// Activity before this counts as old (a new rule doesn't flood you with history).
    var createdAt = Date()
}

/// A category's tint: Claude's palette, by name so it survives design changes.
enum CategoryColor: String, Codable, CaseIterable, Hashable {
    case clay, amber, green, aqua, blue, violet, magenta, red, gray
}

struct InboxCategory: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// SF Symbol.
    var symbol: String
    var color: CategoryColor
    var rules: [Rule] = []
    /// Native notifications.
    var notifies = true
    /// Hidden from the bar and muted; still collects.
    var hidden = false
    /// CI: the default category, whose rules only take repos.
    var isCI = false
    /// What it does by itself when a thing comes in (InboxActions.swift).
    var actions = ActionList()

    /// What the bar and the lists call it; a category still being named is "Untitled".
    var title: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : name }
}

struct InboxGroup: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case people, repos }
    var id = UUID()
    var name: String
    var kind: Kind
    /// Logins (people) or `owner/repo` / `owner/*` (repos).
    var members: [String] = []
}

// MARK: - Things, as fetched

/// GitHub's `authorAssociation`.
enum Association: String, Codable, Hashable {
    case owner, member, collaborator, contributor, firstTimeContributor, firstTimer, mannequin, none

    var isMaintainer: Bool { self == .owner || self == .member || self == .collaborator }
}

struct Person: Codable, Hashable {
    var login: String
    var isBot = false
    var association: Association = .none
    var avatar: URL?
}

struct ThingComment: Codable, Hashable, Identifiable {
    var id: String
    var author: Person
    var at: Date
    var snippet: String
    /// Logins @-mentioned in the body, lowercased.
    var mentions: [String] = []
    /// A review's summary rather than a plain comment.
    var isReview = false
}

enum ReviewState: String, Codable, Hashable {
    case approved, changesRequested, commented, dismissed
}

struct ThingReview: Codable, Hashable, Identifiable {
    var id: String
    var author: Person
    var state: ReviewState
    var at: Date
}

struct ThingThread: Codable, Hashable, Identifiable {
    var id: String
    var isResolved: Bool
    var startedBy: Person
    var lastReplyBy: Person
    /// Id of the latest comment in the thread: a new reply is a new fact.
    var lastReplyID: String
    var lastReplyAt: Date
    var path: String?
    var snippet: String
}

struct ThingCommit: Codable, Hashable, Identifiable {
    var id: String
    var author: String
    var at: Date
}

/// A review someone was asked for, and when: a new request after a review is a new fact.
struct ThingReviewRequest: Codable, Hashable {
    /// A login, or `org/team`.
    var reviewer: String
    var at: Date
}

/// A PR, issue or workflow as last fetched: everything the conditions read.
struct Thing: Codable, Hashable, Identifiable {
    /// `pr:owner/repo#12`, `issue:owner/repo#3`, `workflow:owner/repo:<workflow id>@<branch>`.
    var id: String
    var kind: ThingKind
    var repo: String
    var number: Int?
    var title: String
    var url: URL
    var author: Person?
    var status: ThingStatus = .open
    var labels: [String] = []
    var assignees: [String] = []
    /// Logins, and `org/team` for teams.
    var requestedReviewers: [String] = []
    /// Logins @-mentioned in the body or any comment, lowercased.
    var mentioned: [String] = []
    var createdAt: Date
    var updatedAt: Date
    var comments: [ThingComment] = []
    var reviews: [ThingReview] = []
    var threads: [ThingThread] = []
    var commits: [ThingCommit] = []
    var checks: CheckState?
    var hasConflicts = false
    /// GitHub's mergeStateStatus is BEHIND.
    var behindBase = false
    /// The latest commit's id.
    var headSha: String?
    /// When each current review request was made (the latest `ReviewRequestedEvent` per reviewer).
    var reviewRequests: [ThingReviewRequest] = []
    var greptileScore: Int?
    // Workflows
    var workflowName: String?
    var branch: String?
    var failingJobs: [String] = []
    /// PRs: the size of the change, when GitHub said.
    var additions: Int?
    var deletions: Int?
    var changedFiles: Int?
    /// What Jev made of it (InboxJev.swift), kept across refreshes; nil before it was asked anything.
    var signals: ThingSignals?
}

/// Jev's verdicts on a thing, each asked once for what it was judged on.
struct ThingSignals: Codable, Hashable {
    /// By comment, review or thread reply id: every message Jev read.
    var messages: [String: MessageSignal] = [:]
    var importance: ImportanceSignal?
    /// Whose inbox Jev read it for (a login as `InboxEngine.viewer` writes it): signed in as someone else, it says nothing.
    var viewer: String?
    /// Your latest word there as ever seen: someone's later reply in a thread takes the place of yours in what GitHub
    /// returns, and must not make a question you answered ask again.
    var answeredAt: Date?
}

/// What Jev said of one message; nil where it wasn't sure.
struct MessageSignal: Codable, Hashable {
    var asksMe: Bool?
    var noise: Bool?
}

struct ImportanceSignal: Codable, Hashable {
    /// Nil: Jev wasn't sure.
    var level: Importance?
    /// What it was rated on (the request or assignment and the head commit): a new one is rated again.
    var stamp: String
}

// MARK: - What the engine says

/// Why a thing is in a category, as the row shows it. `key` is its identity: the same key never notifies twice,
/// and Done acknowledges keys.
struct Fact: Codable, Hashable {
    var key: String
    /// The chip, in the rule's words: "Greptile 4/5", "2 unresolved", "last comment: @toksdotdev".
    var label: String
    var tint: FactTint = .neutral
}

enum FactTint: String, Codable, Hashable {
    case neutral, attention, danger, success
}

/// A thing in a category now.
struct InboxEntry: Hashable, Identifiable {
    var thing: Thing
    var categoryID: UUID
    var facts: [Fact]
    /// Every current fact acknowledged.
    var isDone: Bool
    /// Some fact not seen yet.
    var isUnread: Bool
    /// Jev's rating of what it asks of you (a review request, an assignment), when it rated it.
    var importance: Importance?
    var id: String { thing.id }
}

/// What the user did with a thing, persisted by thing id.
struct EntryMarks: Codable, Hashable {
    /// Fact keys seen (opened, or shown and read).
    var seen: Set<String> = []
    /// Fact keys acknowledged with Done.
    var acked: Set<String> = []
    /// Fact keys already notified.
    var notified: Set<String> = []
    var doneAt: Date?
}

/// Resolves what slots name that the engine can't know alone.
struct InboxContext {
    var me: String
    var groups: [InboxGroup] = []
    var contributedRepos: Set<String> = []
    /// `org/team` of every team you're in.
    var myTeams: Set<String> = []
    var now = Date()
    /// What Jev said of things counts (Settings' "Let Jev read new comments"); off, it is as if Jev had said nothing.
    var jevSignals = true
}
