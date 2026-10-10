import Foundation
import SwiftUI

enum CIState: String, Codable {
    case success, failure, pending, none

    var color: Color {
        switch self {
        // Claude's: git-added green, danger red, clay while running (the island design's CI colours).
        case .success: CDS.Git.added
        case .failure: CDS.Text.danger
        case .pending: CDS.clay
        case .none: Theme.tertiary
        }
    }

    var symbol: String {
        switch self {
        case .success: "checkmark.seal.fill"
        case .failure: "xmark.seal.fill"
        case .pending: "clock.fill"
        case .none: "seal.fill"
        }
    }

    var title: String {
        switch self {
        case .success: "Passing"
        case .failure: "Failing"
        case .pending: "Running"
        case .none: "No checks"
        }
    }

    var label: String {
        switch self {
        case .success: "passing"
        case .failure: "failing"
        case .pending: "running"
        case .none: "no checks"
        }
    }
}

struct CIStatus: Codable, Hashable {
    var state: CIState
    var branch: String
    var sha: String?
    var url: URL?
    var failing: [String]
    var checkedAt: Date
    /// Headline of the latest commit on the branch, and when its runs last changed.
    var title: String?
    var updatedAt: Date?
    /// Each workflow on its own (external checks and statuses together are one more).
    var workflows: [Workflow] = []

    struct Workflow: Codable, Hashable {
        /// The workflow's id on GitHub; `Store.externalWorkflowID` for external checks.
        var id: String
        var name: String
        var state: CIState
        var failing: [String]
        var url: URL?
        var updatedAt: Date?
    }
}

struct AppSettings: Codable {
    var pollInterval: Double = 60
    var notifications = true
    var snoozeUntil: Date?
    /// Customized shortcuts by ShortcutAction raw value; missing ones use the defaults.
    var shortcuts: [String: Shortcut]?
    /// Look for new releases in the background (default on).
    var checkUpdates: Bool?
    /// A release you chose to skip: not offered again by automatic checks.
    var skippedVersion: String?
    /// Keep the pill at the middle of its edge: dragging only picks the edge (default off).
    var centerPill: Bool?
}

struct PersistedState: Codable {
    var settings: AppSettings
    var agents: AgentsState?
    var router: RouterState?
    var categories: [InboxCategory]? = nil
    var groups: [InboxGroup]? = nil
    var things: [String: Thing]? = nil
    var marks: [String: EntryMarks]? = nil
    /// Per category, the rules (by id) whose matches were already noted: a category's first look, or a changed rule set,
    /// announces nothing.
    var categoryBaselines: [UUID: Set<UUID>]? = nil
    var ownedRepos: Set<String>? = nil
    var contributedRepos: Set<String>? = nil
    var reposResolvedAt: Date? = nil
    var myTeams: Set<String>? = nil

    init(settings: AppSettings, agents: AgentsState? = nil, router: RouterState? = nil, categories: [InboxCategory]? = nil,
         groups: [InboxGroup]? = nil, things: [String: Thing]? = nil, marks: [String: EntryMarks]? = nil,
         categoryBaselines: [UUID: Set<UUID>]? = nil, ownedRepos: Set<String>? = nil, contributedRepos: Set<String>? = nil,
         reposResolvedAt: Date? = nil, myTeams: Set<String>? = nil) {
        self.settings = settings
        self.agents = agents
        self.router = router
        self.categories = categories
        self.groups = groups
        self.things = things
        self.marks = marks
        self.categoryBaselines = categoryBaselines
        self.ownedRepos = ownedRepos
        self.contributedRepos = contributedRepos
        self.reposResolvedAt = reposResolvedAt
        self.myTeams = myTeams
    }

    /// Tolerant: a file from before the categories (repos, items, ci) loses that data and loads the rest; a part that no
    /// longer decodes is lost alone.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decodeIfPresent(AppSettings.self, forKey: .settings)) ?? AppSettings()
        agents = try? c.decodeIfPresent(AgentsState.self, forKey: .agents)
        router = try? c.decodeIfPresent(RouterState.self, forKey: .router)
        categories = try? c.decodeIfPresent([InboxCategory].self, forKey: .categories)
        groups = try? c.decodeIfPresent([InboxGroup].self, forKey: .groups)
        things = try? c.decodeIfPresent([String: Thing].self, forKey: .things)
        marks = try? c.decodeIfPresent([String: EntryMarks].self, forKey: .marks)
        categoryBaselines = try? c.decodeIfPresent([UUID: Set<UUID>].self, forKey: .categoryBaselines)
        ownedRepos = try? c.decodeIfPresent(Set<String>.self, forKey: .ownedRepos)
        contributedRepos = try? c.decodeIfPresent(Set<String>.self, forKey: .contributedRepos)
        reposResolvedAt = try? c.decodeIfPresent(Date.self, forKey: .reposResolvedAt)
        myTeams = try? c.decodeIfPresent(Set<String>.self, forKey: .myTeams)
    }
}
