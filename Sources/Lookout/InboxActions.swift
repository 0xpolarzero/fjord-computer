import Foundation

// Actions: what a category does by itself when a thing comes in. Pure planning here (which runs are due, which are old
// news), the Store's runner and the real performer below. The user-facing contract is in docs/design/spec/inbox.md.

// MARK: - Model

/// When an action runs for a thing in the category.
enum ActionTrigger: String, Codable, Hashable {
    /// Once, when the thing comes into the category (and again if it left and came back after a while).
    case enter
    /// Once for each new fact the thing gains.
    case eachFact
}

/// Where a session starts.
enum SessionFolder: Codable, Hashable {
    /// The repo's local clone, found by matching the git remotes of the projects Claude knows.
    case clone
    case folder(String)
}

enum ActionKind: Codable, Hashable {
    case session(SessionFolder, prompt: String)
    case comment(String)
    /// Re-run the failed jobs of the failing workflow runs.
    case rerun
}

struct CategoryAction: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: ActionKind
    var trigger: ActionTrigger = .enter

    var title: String {
        switch kind {
        case .session: "Start a Claude session"
        case .comment: "Comment on GitHub"
        case .rerun: "Re-run failed checks"
        }
    }

    var symbol: String {
        switch kind {
        case .session: "sparkles"
        case .comment: "text.bubble"
        case .rerun: "arrow.clockwise"
        }
    }

    func applies(to kind: ThingKind) -> Bool {
        switch self.kind {
        case .session: true
        case .comment: kind != .workflow
        case .rerun: kind != .issue
        }
    }

    static func make(_ kind: ActionKind) -> CategoryAction { CategoryAction(kind: kind) }
}

/// A category's actions. Written as a plain array; a category saved before actions has none.
struct ActionList: Codable, Hashable {
    var items: [CategoryAction] = []
    var isEmpty: Bool { items.isEmpty }

    init(_ items: [CategoryAction] = []) { self.items = items }
    init(from decoder: Decoder) throws { items = try decoder.singleValueContainer().decode([CategoryAction].self) }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(items)
    }
}

extension KeyedDecodingContainer {
    /// Absent key: no actions (what the synthesized coding of `InboxCategory` needs for a file from before them).
    func decode(_ type: ActionList.Type, forKey key: Key) throws -> ActionList {
        try decodeIfPresent(type, forKey: key) ?? ActionList()
    }
}

// MARK: - What happened

/// One run of an action for a thing and a trigger key.
struct ActionRun: Codable, Hashable {
    enum State: String, Codable, Hashable {
        /// Already in the category when the action was made: old, never run.
        case baselined
        case running, done, failed
    }

    var category: UUID
    var thing: String
    var action: UUID
    /// `enter`, or a fact key.
    var trigger: String
    var state: State
    var at: Date
    /// done: "commented", "re-ran 2 jobs", "session started"; failed: why.
    var detail = ""
    /// The comment's page.
    var url: URL?
    /// The Claude app's id of a session started.
    var sessionID: String?
}

/// Everything actions remember: what was already there when each category (or action) began, and each run.
struct ActionLedger: Codable, Equatable {
    struct Baseline: Codable, Equatable {
        /// A fingerprint of the category's rules (see `InboxActions.fingerprint`).
        var rules: String
        var actions: Set<UUID>
    }

    var baselines: [UUID: Baseline] = [:]
    var runs: [String: ActionRun] = [:]

    static func key(_ category: UUID, _ thing: String, _ action: UUID, _ trigger: String) -> String {
        "\(category.uuidString)\u{1F}\(thing)\u{1F}\(action.uuidString)\u{1F}\(trigger)"
    }

    func run(_ category: UUID, _ thing: String, _ action: UUID, _ trigger: String) -> ActionRun? {
        runs[Self.key(category, thing, action, trigger)]
    }

    mutating func set(_ run: ActionRun) { runs[Self.key(run.category, run.thing, run.action, run.trigger)] = run }
}

// MARK: - Planning

enum InboxActions {
    /// Runs per sync; the rest wait for the next.
    static let perSync = 10
    /// How long a thing must have been out of a category before coming back counts as entering again (a workflow that
    /// is re-run and fails again would otherwise be re-run for ever).
    static let reentryCooldown: TimeInterval = 3600
    /// Runs remembered.
    static let maxRuns = 2000

    /// One action due for one thing.
    struct Job: Equatable {
        var category: InboxCategory
        var action: CategoryAction
        var entry: InboxEntry
        /// The trigger keys it answers: `enter`, or the new facts' keys.
        var keys: [String]
        var facts: [Fact]
    }

    // MARK: Loop guard

    /// Who made a fact, when it is about someone's act (a comment, review, commit, reply); nil for facts about state.
    static func author(of key: String, in thing: Thing) -> String? {
        let parts = key.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        let id = parts[1]
        switch parts[0] {
        case "comment", "mention", "last":
            return thing.comments.first { $0.id == id }?.author.login
        case "review", "approved", "changes":
            return thing.reviews.first { $0.id == id }?.author.login ?? thing.comments.first { $0.id == id }?.author.login
        case "commit":
            return thing.commits.first { $0.id == id }?.author
        case "thread":
            return thing.threads.first { $0.id == id }?.lastReplyBy.login
        default:
            return nil
        }
    }

    /// The facts that may trigger an action: not made by you, so an action's own comment (or any act of yours) never
    /// starts another.
    static func triggering(_ entry: InboxEntry, me: String) -> [Fact] {
        let mine = me.lowercased()
        return entry.facts.filter { fact in
            guard let who = author(of: fact.key, in: entry.thing) else { return true }
            return who.lowercased() != mine
        }
    }

    // MARK: Plan

    /// What the rules say, in a number that is the same at every launch: any edit of a rule (not only adding or removing
    /// one) makes what matches it old news.
    static func fingerprint(_ rules: [Rule]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in (try? encoder.encode(rules)) ?? Data() {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// Brings the ledger up to date with the categories (a category, rule set or action seen for the first time takes what
    /// is there as old; runs of what is gone are forgotten) and returns the runs that are due, in the order of the
    /// categories, newest things first.
    static func plan(entries: [InboxEntry], categories: [InboxCategory], ledger: inout ActionLedger, me: String,
                     now: Date = Date()) -> [Job] {
        let byCategory = Dictionary(grouping: entries, by: \.categoryID)
        let known = Set(categories.map(\.id))
        // Baselines: what is there when a category's rules change, or an action is added, is old.
        for category in categories {
            let ruleIDs = fingerprint(category.rules)
            let actionIDs = Set(category.actions.items.map(\.id))
            let before = ledger.baselines[category.id]
            let all = before == nil || before!.rules != ruleIDs
            let fresh = all ? category.actions.items : category.actions.items.filter { !(before?.actions.contains($0.id) ?? false) }
            for action in fresh {
                for entry in byCategory[category.id] ?? [] where action.applies(to: entry.thing.kind) {
                    for key in ["enter"] + entry.facts.map(\.key) {
                        let existing = ledger.run(category.id, entry.id, action.id, key)
                        if existing == nil {
                            ledger.set(ActionRun(category: category.id, thing: entry.id, action: action.id, trigger: key,
                                                 state: .baselined, at: now))
                        }
                    }
                }
            }
            let baseline = ActionLedger.Baseline(rules: ruleIDs, actions: actionIDs)
            if before != baseline { ledger.baselines[category.id] = baseline }
        }
        for id in ledger.baselines.keys where !known.contains(id) { ledger.baselines[id] = nil }

        // Forget: runs of a category or action that is gone; entering records of a thing that has been out for a while.
        let actionIDs = Set(categories.flatMap { $0.actions.items.map(\.id) })
        let inside = Set(entries.filter { !triggering($0, me: me).isEmpty }.map { "\($0.categoryID.uuidString)\u{1F}\($0.id)" })
        for (key, run) in ledger.runs {
            if !known.contains(run.category) || !actionIDs.contains(run.action) {
                ledger.runs[key] = nil
            } else if run.trigger == "enter", run.state != .running,
                      !inside.contains("\(run.category.uuidString)\u{1F}\(run.thing)"),
                      now.timeIntervalSince(run.at) > reentryCooldown {
                ledger.runs[key] = nil
            }
        }
        if ledger.runs.count > maxRuns {
            let drop = ledger.runs.filter { $0.value.state != .running }.sorted { $0.value.at < $1.value.at }
                .prefix(ledger.runs.count - maxRuns)
            for (key, _) in drop { ledger.runs[key] = nil }
        }
        return due(entries: entries, categories: categories, ledger: ledger, me: me)
    }

    /// The runs due now, without changing anything.
    static func due(entries: [InboxEntry], categories: [InboxCategory], ledger: ActionLedger, me: String) -> [Job] {
        var jobs: [Job] = []
        for category in categories where !category.actions.isEmpty {
            // Not yet taken in: nothing is due (the baseline comes first).
            guard let baseline = ledger.baselines[category.id], baseline.rules == fingerprint(category.rules) else { continue }
            let mine = entries.filter { $0.categoryID == category.id && !$0.isDone }
                .sorted { ($0.thing.updatedAt, $0.id) > ($1.thing.updatedAt, $1.id) }
            for entry in mine {
                let facts = triggering(entry, me: me)
                guard !facts.isEmpty else { continue }
                for action in category.actions.items where action.applies(to: entry.thing.kind) {
                    guard baseline.actions.contains(action.id) else { continue }
                    switch action.trigger {
                    case .enter:
                        if ledger.run(category.id, entry.id, action.id, "enter") == nil {
                            jobs.append(Job(category: category, action: action, entry: entry, keys: ["enter"], facts: facts))
                        }
                    case .eachFact:
                        let new = facts.filter { ledger.run(category.id, entry.id, action.id, $0.key) == nil }
                        if !new.isEmpty {
                            jobs.append(Job(category: category, action: action, entry: entry, keys: new.map(\.key), facts: new))
                        }
                    }
                }
            }
        }
        return jobs
    }

    // MARK: Words

    /// `{title} {url} {number} {repo} {author}` filled in.
    static func substitute(_ text: String, thing: Thing) -> String {
        let values: [(String, String)] = [
            ("{title}", thing.title), ("{url}", thing.url.absoluteString), ("{number}", thing.number.map(String.init) ?? ""),
            ("{repo}", thing.repo), ("{author}", thing.author.map { "@" + $0.login } ?? ""),
        ]
        return values.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    static func reference(_ thing: Thing) -> String {
        switch thing.kind {
        case .workflow: "\(thing.repo) · \(thing.workflowName ?? "workflow") on \(thing.branch ?? "its branch")"
        default: "\(thing.repo)#\(thing.number ?? 0)"
        }
    }

    /// A session's first message: your prompt, then the event's context.
    static func prompt(_ text: String, category: String, thing: Thing, facts: [Fact]) -> String {
        var lines = ["Context, from the “\(category)” category of the Lookout inbox:",
                     "- Title: \(thing.title)", "- URL: \(thing.url.absoluteString)",
                     "- \(thing.kind == .pr ? "Pull request" : thing.kind == .issue ? "Issue" : "Workflow"): \(reference(thing))"]
        if !facts.isEmpty { lines.append("- Why it is here: " + facts.map(\.label).joined(separator: " · ")) }
        if thing.kind == .workflow, !thing.failingJobs.isEmpty { lines.append("- Failing jobs: " + thing.failingJobs.joined(separator: ", ")) }
        if let last = thing.comments.max(by: { $0.at < $1.at }) {
            lines.append("- Last comment, by @\(last.author.login): “\(last.snippet)”")
        }
        let body = substitute(text, thing: thing).trimmingCharacters(in: .whitespacesAndNewlines)
        return (body.isEmpty ? "" : body + "\n\n") + lines.joined(separator: "\n")
    }

    /// A short title for the session.
    static func sessionTitle(_ thing: Thing) -> String {
        SessionStart.cleanTitle(thing.kind == .workflow ? "CI: \(thing.title)" : "\(thing.repo)#\(thing.number ?? 0) \(thing.title)")
    }

    // MARK: Chips

    /// What a row says about an action: the state of its latest run, or that it is waiting.
    struct Chip: Equatable, Identifiable {
        enum Target: Equatable { case session(String), url(URL) }
        var id: UUID
        var label: String
        var tint: FactTint
        var target: Target?
        var help: String
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }

    static func chips(for entry: InboxEntry, category: InboxCategory, ledger: ActionLedger, me: String, now: Date = Date()) -> [Chip] {
        guard !category.actions.isEmpty else { return [] }
        let queued = Set(due(entries: [entry], categories: [category], ledger: ledger, me: me).map(\.action.id))
        var out: [Chip] = []
        for action in category.actions.items where action.applies(to: entry.thing.kind) {
            let latest = ledger.runs.values
                .filter { $0.category == category.id && $0.thing == entry.id && $0.action == action.id && $0.state != .baselined }
                .max { $0.at < $1.at }
            if let run = latest {
                out.append(chip(run, action: action, now: now))
            } else if queued.contains(action.id) {
                out.append(Chip(id: action.id, label: "queued", tint: .neutral, target: nil, help: "\(action.title) runs on the next refresh"))
            }
        }
        return out
    }

    private static func chip(_ run: ActionRun, action: CategoryAction, now: Date) -> Chip {
        switch run.state {
        case .running, .baselined:
            return Chip(id: action.id, label: "running…", tint: .neutral, target: nil, help: action.title)
        case .failed:
            let reason = run.detail.count > 48 ? String(run.detail.prefix(47)) + "…" : run.detail
            return Chip(id: action.id, label: "failed: \(reason)", tint: .danger, target: nil, help: "\(action.title) failed: \(run.detail)")
        case .done:
            switch action.kind {
            case .session:
                return Chip(id: action.id, label: "session started \(ago(run.at, now: now))", tint: .neutral,
                            target: run.sessionID.map { .session($0) }, help: "Open the session in Claude")
            case .comment:
                return Chip(id: action.id, label: "commented", tint: .neutral, target: run.url.map { .url($0) },
                            help: "Open the comment on GitHub")
            case .rerun:
                return Chip(id: action.id, label: run.detail.isEmpty ? "re-ran" : run.detail, tint: .neutral, target: nil,
                            help: "Failed checks were re-run \(ago(run.at, now: now))")
            }
        }
    }
}

// MARK: - Doing

/// A workflow run that failed, and what re-running it takes.
struct FailedRun: Equatable {
    var id: Int
    var name: String
    var url: URL?
}

/// What actions do in the world. The Store has the real one; tests and the playground have their own (or none).
@MainActor
protocol ActionPerformer: AnyObject {
    /// Starts a session in `folder`; its id in the Claude app.
    func startSession(folder: String, prompt: String, title: String) async throws -> String
    /// Posts a comment; its page when GitHub says.
    func comment(repo: String, number: Int, body: String) async throws -> URL?
    /// The failed runs that re-running would take, for a PR's head commit or a workflow thing.
    func failedRuns(for thing: Thing) async throws -> [FailedRun]
    /// Re-runs one run's failed jobs; how many jobs.
    func rerun(repo: String, run: FailedRun) async throws -> Int
    /// The local clone of a repo, if one of the known project folders is.
    func clone(of repo: String) -> String?
}

struct ActionFailure: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension InboxActions {
    /// Does one job; the run that records it.
    @MainActor
    static func perform(_ job: Job, with performer: ActionPerformer, now: Date = Date()) async -> ActionRun {
        let thing = job.entry.thing
        var run = ActionRun(category: job.category.id, thing: thing.id, action: job.action.id, trigger: job.keys.first ?? "enter",
                            state: .done, at: now)
        do {
            switch job.action.kind {
            case .session(let where_, let text):
                let folder: String
                switch where_ {
                case .folder(let path): folder = path
                case .clone:
                    guard let found = performer.clone(of: thing.repo) else {
                        throw ActionFailure("no local clone of \(thing.repo) among your projects")
                    }
                    folder = found
                }
                run.sessionID = try await performer.startSession(
                    folder: folder, prompt: prompt(text, category: job.category.name, thing: thing, facts: job.facts),
                    title: sessionTitle(thing))
                run.detail = "session started"
            case .comment(let text):
                guard let number = thing.number, thing.kind != .workflow else { throw ActionFailure("only PRs and issues take comments") }
                let body = substitute(text, thing: thing).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { throw ActionFailure("the comment is empty") }
                run.url = try await performer.comment(repo: thing.repo, number: number, body: body)
                run.detail = "commented"
            case .rerun:
                let failed = try await performer.failedRuns(for: thing)
                guard !failed.isEmpty else { throw ActionFailure("no failed run to re-run") }
                var jobs = 0
                for failure in failed { jobs += try await performer.rerun(repo: thing.repo, run: failure) }
                run.detail = jobs == 0 ? "re-ran" : "re-ran \(jobs) job\(jobs == 1 ? "" : "s")"
            }
        } catch {
            run.state = .failed
            run.detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        run.at = now
        return run
    }

    /// What "Try on latest match" shows: nothing is done.
    @MainActor
    static func preview(_ action: CategoryAction, category: String, thing: Thing, facts: [Fact],
                        performer: ActionPerformer?) async -> [String] {
        guard action.applies(to: thing.kind) else { return ["Doesn't apply to \(thing.kind.label.lowercased()): skipped."] }
        var lines = ["On \(reference(thing)): \(thing.title)"]
        switch action.kind {
        case .session(let where_, let text):
            switch where_ {
            case .folder(let path): lines.append("Starts a session in \(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).")
            case .clone:
                if let performer {
                    lines.append(performer.clone(of: thing.repo).map { "Starts a session in \($0.replacingOccurrences(of: NSHomeDirectory(), with: "~"))." }
                                 ?? "No local clone of \(thing.repo) among your projects: this would fail.")
                } else {
                    lines.append("Starts a session in the local clone of \(thing.repo).")
                }
            }
            lines.append("First message:")
            lines.append(prompt(text, category: category, thing: thing, facts: facts))
        case .comment(let text):
            let body = substitute(text, thing: thing)
            lines.append("Comments on \(reference(thing)):")
            lines.append(body.isEmpty ? "(empty: this would fail)" : body)
        case .rerun:
            if let performer, let failed = try? await performer.failedRuns(for: thing) {
                lines.append(failed.isEmpty ? "No failed run: nothing would be re-run."
                             : "Would re-run the failed jobs of: " + failed.map(\.name).joined(separator: ", ") + ".")
            } else {
                lines.append("Would re-run the failed jobs of its failing workflow runs.")
            }
        }
        return lines
    }
}

// MARK: - Local clones

enum LocalClones {
    /// `owner/repo` (lowercased) from a remote URL on GitHub.
    static func repo(fromRemote url: String) -> String? {
        guard let host = url.range(of: "github.com", options: .caseInsensitive) else { return nil }
        var rest = url[host.upperBound...]
        guard let first = rest.first, first == ":" || first == "/" else { return nil }
        rest = rest.dropFirst()
        var parts = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        parts = Array(parts.prefix(2))
        if parts[1].lowercased().hasSuffix(".git") { parts[1] = String(parts[1].dropLast(4)) }
        return parts.joined(separator: "/").lowercased()
    }

    /// The GitHub repos a folder's git config names as remotes.
    static func remotes(of folder: String) -> [String] {
        let fm = FileManager.default
        let dotGit = (folder as NSString).appendingPathComponent(".git")
        var gitDir = dotGit
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dotGit, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            // A worktree: `gitdir: <repo>/.git/worktrees/<name>`; the config is the repo's.
            guard let text = try? String(contentsOfFile: dotGit, encoding: .utf8),
                  let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return [] }
            gitDir = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
            if let range = gitDir.range(of: "/worktrees/") { gitDir = String(gitDir[..<range.lowerBound]) }
        }
        guard let config = try? String(contentsOfFile: (gitDir as NSString).appendingPathComponent("config"), encoding: .utf8) else { return [] }
        return config.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("url") else { return nil }
            guard let eq = t.firstIndex(of: "=") else { return nil }
            return repo(fromRemote: t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces))
        }
    }

    /// The folder (shortest path first, so a checkout wins over its worktrees) whose remotes name `repo`.
    static func find(_ repo: String, in folders: [String], remotes: (String) -> [String] = remotes(of:)) -> String? {
        let wanted = repo.lowercased()
        return folders.filter { !$0.isEmpty }.sorted { ($0.count, $0) < ($1.count, $1) }
            .first { remotes($0).contains(wanted) }
    }
}

// MARK: - The Store's side

extension Store {
    /// Called after every inbox refresh: runs the actions that are due, off the refresh.
    func scheduleActions() {
        guard categories.contains(where: { !$0.actions.isEmpty }) || !actionLedger.runs.isEmpty || !actionLedger.baselines.isEmpty
        else { return }
        Task { @MainActor in await runActions() }
    }

    private var resolvedPerformer: ActionPerformer? {
        if let actionPerformer { return actionPerformer }
        guard persists, !Store.isDemo else { return nil }
        let real = StoreActionPerformer(store: self)
        actionPerformer = real
        return real
    }

    /// Takes in what changed (baselines) and runs what is due, at most `actionLimit` per call.
    func runActions(now: Date = Date()) async {
        guard let performer = resolvedPerformer, let me = me?.login, !me.isEmpty else { return }
        guard !actionsBusy else { actionsAgain = true; return }
        actionsBusy = true
        defer { actionsBusy = false }
        repeat {
            actionsAgain = false
            var ledger = actionLedger
            let jobs = InboxActions.plan(entries: entries, categories: categories, ledger: &ledger, me: me, now: now)
            let batch = Array(jobs.prefix(actionLimit))
            for job in batch {
                for key in job.keys {
                    ledger.set(ActionRun(category: job.category.id, thing: job.entry.id, action: job.action.id, trigger: key,
                                         state: .running, at: now))
                }
            }
            if ledger != actionLedger { actionLedger = ledger }
            for job in batch {
                let result = await InboxActions.perform(job, with: performer, now: now)
                var next = actionLedger
                for key in job.keys {
                    var run = result
                    run.trigger = key
                    next.set(run)
                }
                actionLedger = next
            }
        } while actionsAgain
    }

    /// Takes what is in the categories now as old, for the actions they have (called when a category is saved).
    func baselineActions(now: Date = Date()) {
        guard let me = me?.login, !me.isEmpty else { return }
        var ledger = actionLedger
        _ = InboxActions.plan(entries: entries, categories: categories, ledger: &ledger, me: me, now: now)
        if ledger != actionLedger { actionLedger = ledger }
    }

    func actionChips(for entry: InboxEntry) -> [InboxActions.Chip] {
        guard let category = categories.first(where: { $0.id == entry.categoryID }), !category.actions.isEmpty else { return [] }
        return InboxActions.chips(for: entry, category: category, ledger: actionLedger, me: me?.login ?? "")
    }

    /// The most recently updated thing the rules match, with its facts: what "Try on latest match" tries on.
    func latestMatch(of rules: [Rule]) -> (thing: Thing, facts: [Fact])? {
        let context = inboxContext
        var best: (Thing, [Fact])?
        for thing in things.values {
            for rule in rules {
                guard let facts = InboxEngine.facts(rule, thing, marks: nil, context: context) else { continue }
                if best == nil || thing.updatedAt > best!.0.updatedAt { best = (thing, facts) }
                break
            }
        }
        return best.map { (thing: $0.0, facts: $0.1) }
    }

    func openActionTarget(_ target: InboxActions.Chip.Target) {
        switch target {
        case .session(let id): openAgent(id)
        case .url(let url):
            if let interceptOpen { interceptOpen("Open on GitHub · comment") } else { Link.open(url) }
        }
    }

    // MARK: Persistence (its own small file next to the state)

    var actionsFile: URL? { stateFileURL?.deletingLastPathComponent().appendingPathComponent("actions.json") }

    func loadActions() {
        guard persists, let url = actionsFile, let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard var ledger = try? dec.decode(ActionLedger.self, from: data) else { return }
        // Running when the app quit: not retried (it may have happened), said as failed.
        for (key, run) in ledger.runs where run.state == .running {
            var r = run
            r.state = .failed
            r.detail = "interrupted"
            ledger.runs[key] = r
        }
        actionLedger = ledger
    }

    func saveActions() {
        guard persists, let url = actionsFile else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(actionLedger) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - The real performer

@MainActor
final class StoreActionPerformer: ActionPerformer {
    private unowned let store: Store
    init(store: Store) { self.store = store }

    func clone(of repo: String) -> String? { LocalClones.find(repo, in: store.knownFolders) }

    /// The Router's way of making a session (`SessionStart`): a CLI session made in the folder with a uuid, which the Claude
    /// app imports (`claude://resume`) and starts, and which then registers as a peer, so the Router sees it. The prompt is
    /// the session's first turn, run by Claude Code itself before the import.
    func startSession(folder: String, prompt: String, title: String) async throws -> String {
        guard let binary = store.routerAgent.claudeCode?.path,
              let peersDir = store.routerFiles?.claudeDir.appendingPathComponent("sessions") else {
            throw ActionFailure("Claude Code wasn't found")
        }
        let uuid = UUID().uuidString.lowercased()
        let output = try await OneShot.run(binary, SessionStart.promptArguments(uuid: uuid, prompt: prompt),
                                           cwd: URL(fileURLWithPath: folder), timeout: SessionStart.firstTurnWait)
        _ = try OneShot.result(output)
        guard let url = SessionStart.importURL(uuid: uuid) else { throw ActionFailure("couldn't make the link") }
        if let intercept = store.interceptOpen { intercept("New Claude session in \(store.folderName(folder))") } else { Link.open(url) }
        _ = try await SessionStart.waitForPeer(uuid: uuid, dir: peersDir)
        return "local_\(uuid)"
    }

    func comment(repo: String, number: Int, body: String) async throws -> URL? {
        let data = try await store.gh.post("/repos/\(repo)/issues/\(number)/comments", ["body": body])
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["html_url"] as? String).flatMap { URL(string: $0) }
    }

    func failedRuns(for thing: Thing) async throws -> [FailedRun] {
        var query = ["per_page": "50"]
        var workflow: Int?
        switch thing.kind {
        case .pr:
            guard let sha = thing.headSha else { throw ActionFailure("its head commit isn't known yet") }
            query["head_sha"] = sha
        case .workflow:
            // `workflow:owner/repo:<id>@<branch>`
            let id = thing.id.split(separator: ":").last.map { String($0.split(separator: "@").first ?? "") } ?? ""
            guard let number = Int(id) else { throw ActionFailure("checks that aren't GitHub Actions can't be re-run") }
            workflow = number
            query["branch"] = thing.branch ?? ""
            query["event"] = "push"
        case .issue:
            return []
        }
        let runs: GHWorkflowRuns = try await store.gh.get("/repos/\(thing.repo)/actions/runs", query)
        var seen = Set<Int>()
        var out: [FailedRun] = []
        // Newest first: the first of each workflow is its latest run.
        for run in runs.workflowRuns where seen.insert(run.workflowId).inserted {
            if let workflow, run.workflowId != workflow { continue }
            guard let id = run.id, run.status == "completed", ["failure", "timed_out"].contains(run.conclusion ?? "") else { continue }
            out.append(FailedRun(id: id, name: run.name, url: run.htmlUrl))
        }
        return out
    }

    private struct Jobs: Decodable {
        struct Job: Decodable { let conclusion: String? }
        let jobs: [Job]
    }

    func rerun(repo: String, run: FailedRun) async throws -> Int {
        let jobs: Jobs? = try? await store.gh.get("/repos/\(repo)/actions/runs/\(run.id)/jobs", ["filter": "latest", "per_page": "100"])
        try await store.gh.post("/repos/\(repo)/actions/runs/\(run.id)/rerun-failed-jobs")
        return jobs?.jobs.filter { ["failure", "timed_out"].contains($0.conclusion ?? "") }.count ?? 0
    }
}

extension SessionStart {
    /// A session whose first turn is `prompt`, run headlessly by Claude Code (its permissions are those of your settings).
    static func promptArguments(uuid: String, prompt: String) -> [String] {
        ["-p", prompt, "--session-id", uuid, "--output-format", "json"]
    }

    /// How long that first turn may take.
    static let firstTurnWait: TimeInterval = 900
}
