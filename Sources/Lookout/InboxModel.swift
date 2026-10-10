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

/// Someone a slot names.
enum PersonRef: Codable, Hashable {
    case me
    case user(String)
    case group(UUID)
    /// GitHub's role on the thing's repo: owner, member or collaborator.
    case maintainers
    /// Accounts GitHub marks as bots.
    case bots
}

/// Somewhere a slot names.
enum RepoRef: Codable, Hashable {
    case repo(String)
    /// Every repo of an owner: `owner/*`.
    case owner(String)
    case group(UUID)
    case owned
    /// Repos with a merged PR of yours.
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
struct Scope: Codable, Hashable {
    var kind: ThingKind
    var by: Pick<PersonRef>?
    var to: Pick<PersonRef>?
    var toRoles: Set<ToRole> = Set(ToRole.allCases)
    /// Required for workflows.
    var `in`: Pick<RepoRef>?
    /// Workflows: branches; nil is the repo's default branch.
    var on: [String]?
    /// Workflows: names; nil is every workflow.
    var named: [String]?
}

enum CheckState: String, Codable, CaseIterable, Hashable {
    case failing, pending, passing
}

enum ThingStatus: String, Codable, CaseIterable, Hashable {
    case open, draft, merged, closed
}

/// A fact a rule asks for. Activity conditions are events since you last marked the thing done;
/// the others are true or not right now.
enum Condition: Codable, Hashable {
    // Activity
    case newComment(by: Pick<PersonRef>)
    case newReview(by: Pick<PersonRef>)
    case newCommits(by: Pick<PersonRef>)
    case mentions(Pick<PersonRef>)
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
    // Status
    /// PRs/issues: draft, ready (= open and not draft), merged, closed. `.open` here means ready for review.
    case status(Set<ThingStatus>)
    case labeled(Pick<String>)
    case noActivity(days: Int)
    // Signals
    case greptileBelow(Int)
    // Workflows
    case workflow(Set<CheckState>)
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
    var greptileScore: Int?
    // Workflows
    var workflowName: String?
    var branch: String?
    var failingJobs: [String] = []
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
    var ownedRepos: Set<String> = []
    var contributedRepos: Set<String> = []
    var now = Date()
}
