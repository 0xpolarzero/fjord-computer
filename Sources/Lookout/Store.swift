import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class Store {
    /// Demo and snapshot runs: never touch the Keychain (a new build would stop on an access prompt).
    nonisolated static let isDemo = CommandLine.arguments.contains { ["--demo", "--snapshot", "--playground", "--playground-shots"].contains($0) }

    // The inbox: categories of things (see InboxModel.swift, InboxStore.swift).
    var categories: [InboxCategory] = InboxStore.defaultCategories {
        didSet { inboxRevision &+= 1; persistedRevision &+= 1; logCategories(from: oldValue) }
    }
    var groups: [InboxGroup] = [] {
        didSet { inboxRevision &+= 1; persistedRevision &+= 1; logGroups(from: oldValue) }
    }
    /// Who is changing the categories and groups now, for the log (see `InboxLog`); nil is the editor.
    @ObservationIgnored var inboxSource: InboxChangeSource?
    /// Where those log lines go; the tests read them.
    @ObservationIgnored var inboxLog: (String) -> Void = InboxLog.write
    var things: [String: Thing] = [:] {
        didSet { inboxRevision &+= 1; persistedRevision &+= 1; resolveWaits() }
    }
    var marks: [String: EntryMarks] = [:] {
        didSet { inboxRevision &+= 1; persistedRevision &+= 1 }
    }
    /// Per category, the rules (by id) whose matches were already noted: a category's first look, or a changed rule set,
    /// announces nothing.
    var categoryBaselines: [UUID: Set<UUID>] = [:] {
        didSet { persistedRevision &+= 1 }
    }
    /// The repos you own and those you merged a PR in (what `Repos I own` and `Repos I contribute to` mean), kept so the
    /// editor's preview has them at launch.
    var ownedRepos: Set<String> = [] {
        didSet { inboxRevision &+= 1; persistedRevision &+= 1 }
    }
    var contributedRepos: Set<String> = [] {
        didSet { inboxRevision &+= 1; persistedRevision &+= 1 }
    }
    /// The teams you're in, `org/team` (what `My teams` means), resolved with the repos.
    var myTeams: Set<String> = [] {
        didSet { inboxRevision &+= 1; persistedRevision &+= 1 }
    }
    /// What the categories' actions have done and what was already there when they began (InboxActions.swift); kept in its
    /// own file next to the state.
    var actionLedger = ActionLedger() {
        didSet { saveActions() }
    }
    /// Does what actions do; nil is the real one (and nothing at all in the playground and tests).
    @ObservationIgnored var actionPerformer: ActionPerformer?
    @ObservationIgnored var actionsBusy = false
    /// The categories page's undo history while it is open (⌘Z there is the editor's, not Done's).
    @ObservationIgnored var categoryHistory: CategoryHistory?
    /// Rules were edited and the actions have not yet taken in what they match: nothing runs until they have.
    @ObservationIgnored var baselinePending = false
    @ObservationIgnored var baselineTask: Task<Void, Never>?
    @ObservationIgnored var actionsAgain = false
    /// What the last inbox refresh failed at, if it did (InboxSync.swift); the things it had stay.
    var inboxError: String?
    /// Repos (lowercased) GitHub said don't exist, or can't be seen: their chips are red and block Save.
    var missingRepos: Set<String> = []
    /// What GitHub said of each repo named, this session (lowercased name to its canonical name).
    @ObservationIgnored var repoAnswers: [String: String] = [:]
    /// Saved repo names were checked against GitHub's canonical ones this launch.
    @ObservationIgnored var repoNamesChecked = false
    @ObservationIgnored var repoNamesChecking = false
    /// When ownedRepos and contributedRepos were last resolved (at most daily).
    @ObservationIgnored var reposResolvedAt: Date? {
        didSet { persistedRevision &+= 1 }
    }
    /// When myTeams was last resolved (this session; at most daily).
    @ObservationIgnored var teamsResolvedAt: Date?
    /// Default branches found for workflow things, by repo.
    @ObservationIgnored var defaultBranches: [String: String] = [:]
    /// A commit's headline by repo, asked once per commit (see `ciHeadline`).
    @ObservationIgnored var headlines: [String: (commit: String, title: String)] = [:]
    /// When a thing was first missing from a refresh: its marks are dropped after 30 days of that.
    @ObservationIgnored var goneSince: [String: Date] = [:]
    /// Bumped on every inbox change: the memo key for entries.
    private(set) var inboxRevision = 0
    @ObservationIgnored var inboxMemo = InboxStore.Memo()
    /// Done, taken back with ⌘Z or the inbox's undo line.
    let undoStack = UndoStack()
    var settings = AppSettings() {
        didSet {
            persistedRevision &+= 1
            armSnoozeExpiry()
            save()
        }
    }

    /// Claude sessions extension (see Agents.swift).
    var agents = AgentsState() {
        didSet {
            agentCache = nil
            persistedRevision &+= 1
            if !ingesting { claudeStamp.revision += 1 }
            refreshFolderNames()
            save()
        }
    }
    /// The Router (see Router.swift): its cards, its decision log and the changes it made.
    var router = RouterState() {
        didSet {
            routerRevision &+= 1
            persistedRevision &+= 1
            if oldValue.cards != router.cards { countCardChanges(from: oldValue.cards) }
            // Worked out again only if what it is made of changed: a session's stamps or an open card changing leave it (and
            // what draws it) alone.
            if oldValue.decisions != router.decisions || oldValue.summaries != router.summaries || oldValue.cards != router.cards {
                let next = RouterPage.history(cards: router.cards, decisions: router.decisions, summaries: router.summaries)
                if next != routerHistory { routerHistory = next }
            }
            save()
        }
    }
    /// The Router page's history (see `RouterPage.history`), worked out when the router changes and only then: the page
    /// reads it on every redraw.
    private(set) var routerHistory: [RouterPage.Entry] = []
    /// Bumped on every change to `router`: a cheap memo/animation key.
    private(set) var routerRevision = 0
    /// How many times each card has changed (see `countCardChanges`).
    @ObservationIgnored var cardRevisions: [String: Int] = [:]
    /// The question forms Lookout's hook holds, by Claude Code session id (`ClaudeSession.cliID`).
    var pendingForms: [String: PendingForm] = [:]
    /// Why installing or removing the form hook failed, if it did.
    var routerHookError: String?
    /// The form hook as last checked (nil until the Router has been switched on in this run).
    var routerHookStatus: FormHookInstaller.Status?
    /// Lookout's Claude Code plugin as last checked (nil until the Router has been switched on in this run, or in a test
    /// that stands in no CLI), and why installing or removing it failed, if it did.
    var routerPluginStatus: ClaudePluginInstaller.Status?
    var routerPluginError: String?
    /// Every project's name, with as much of its path as tells it from another of the same name (`customer-a/app`): worked
    /// out when the folders change, not by each view that names a project. Only a change in it redraws what reads it.
    var folderNames: [String: String] = [:]
    /// The folders `folderNames` was worked out for: the work is skipped while they are the same.
    @ObservationIgnored var namedFoldersSeen: Set<String>?
    var claudeSessions: [String: ClaudeSession] = [:] {
        didSet {
            agentCache = nil
            refreshFolderNames()
        }
    }
    var claudeActivity: [String: ClaudeActivity] = [:] {
        didSet {
            agentCache = nil
        }
    }
    /// Bumped when a recent session ages out of the list (see `Store.recentWindow`).
    var recentTick = 0 {
        didSet {
            agentCache = nil
        }
    }
    @ObservationIgnored var recentExpiry: Timer?
    /// Subagents and commands still running in sessions whose turn is over.
    var claudeTasks: [String: [ClaudeTask]] = [:] {
        didSet {
            agentCache = nil
        }
    }
    /// Filled in right after launch (see `start`): the Keychain read stays off the main thread.
    var hasTypesafeKey = false
    var iconError: String?
    var claudeLink: ClaudeLink = .off

    var me: GHUser? {
        didSet { if let name = me?.login, name != login { login = name } }
    }
    /// Who `me` was last time, kept so the inbox's "me" rules (by me, to me, Repos I own) match at launch, before GitHub
    /// answers who the token is; a sign-in as someone else replaces it.
    private(set) var login = "" {
        didSet { inboxRevision &+= 1; persistedRevision &+= 1 }
    }
    var tokenSource: TokenSource?
    var authError: String?
    /// The first look at the account got no answer from GitHub (no network yet, a VPN down): nothing is known of the token, so
    /// this is a sync problem, not a sign-in one, and the cached rows stay.
    var unreachable = false
    var isSyncing = false
    var lastSync: Date?
    var rateRemaining: Int?
    /// When the GitHub rate limit resets, as of the last sync.
    @ObservationIgnored var rateResetsAt: Date?
    var suggestions: [String] = []

    @ObservationIgnored let gh = GitHubClient()
    @ObservationIgnored let notifier = Notifier()
    @ObservationIgnored let updater = Updater()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var hubOpen = false
    @ObservationIgnored private var systemAsleep = false
    @ObservationIgnored private var pollNow = false
    /// Where the token comes from; replaced in tests (the real one can spawn `gh`).
    @ObservationIgnored var resolveToken: @Sendable () -> (String, TokenSource)? = { TokenProvider.resolve() }
    /// Counts the changes made in Settings; the token held was found under `foundAt`, and is looked for again once they differ.
    @ObservationIgnored private var credentialsChanged = 0
    @ObservationIgnored private var foundAt = 0
    /// A token was just saved or taken away: the sign-in that fails next is its result and is said aloud (a poll's isn't).
    @ObservationIgnored private(set) var awaitingSignIn = false
    @ObservationIgnored private var lastAuthAttempt: Date?
    @ObservationIgnored private var authRetry = false
    @ObservationIgnored private var refreshQueued = false
    /// Signed out, polls look for a new token this rarely: each look can spawn `gh auth token`.
    private static let authBackoff: TimeInterval = 300
    @ObservationIgnored private var sleeper: Task<Void, Never>?
    /// When the sleeper is due to wake.
    @ObservationIgnored private var sleeperWakes: Date?
    /// The reset an immediate check was already made for (see `pollAll`): never twice for the same one, so a check that
    /// fails (offline, keeping the spent budget and that reset) can't start another at once, and another.
    @ObservationIgnored private var retriedReset: Date?
    @ObservationIgnored private var sleepObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var saveDirty = false
    /// Bumped by every persisted property's didSet: a poll saves only if this moved.
    @ObservationIgnored private var persistedRevision = 0
    /// `persistedRevision` as of the last `save()`: a poll saves whatever changed since, whoever changed it.
    @ObservationIgnored private var savedRevision = 0
    /// When the one-shot Claude timer fires (it only ever moves earlier until it does).
    @ObservationIgnored private var claudeDeadline: Date?
    @ObservationIgnored var persists = true
    /// Stops the shortcut recorder that is listening, if any. While one is, the panel's key handler stands down
    /// and the global hotkeys are released, so the recorder sees every combination.
    @ObservationIgnored private var stopRecorder: (() -> Void)?
    var isRecordingShortcut: Bool { stopRecorder != nil }
    @ObservationIgnored var onRecordingShortcutChange: ((Bool) -> Void)?
    /// Shows the inbox: on a category with a thing selected (a banner for it), or on the first category (a summary's).
    @ObservationIgnored var onOpenInbox: ((_ category: UUID?, _ thing: String?) -> Void)?
    /// Registers a global shortcut system-wide; `false` when the system refuses it.
    @ObservationIgnored var onGlobalShortcutChange: ((ShortcutAction, Shortcut) -> Bool)?
    /// The system-wide shortcuts the system last refused to register (another app holds the key), by the key it refused:
    /// one still stored does nothing, and Settings says so.
    var refusedShortcuts: [ShortcutAction: Shortcut] = [:]
    /// Cards the feed just made, or that Jev's triage found need you (for banners).
    @ObservationIgnored var onNewRouterCards: (([RouterCard]) -> Void)?
    /// What finished turns ended on, by Jev (see RouterTriage.swift).
    @ObservationIgnored let routerTriager = RouterTriager()
    /// Whether the Claude app is in front (tests answer for it).
    @ObservationIgnored var claudeIsFrontmost: () -> Bool = { Claude.isFrontmost }
    /// The Router was just switched on: its open cards are settled against how things are now at the next feed.
    @ObservationIgnored var routerReconcilePending = false
    /// The forms folder has been read since the Router was switched on: until then no form is known to be gone.
    @ObservationIgnored var routerFormsLoaded = false
    /// The sessions whose background work the last read looked at (see `ClaudeSnapshot.taskInventory`); nil until a read
    /// has said (a test feeding sessions by hand: every one).
    @ObservationIgnored var claudeTaskInventory: Set<String>?
    @ObservationIgnored let formBridge = FormBridge()
    /// Claude Code's binary, which the Router's runs use.
    @ObservationIgnored lazy var routerStatus = RouterStatus()
    /// Your messages to the Router, as typed runs (each its own).
    @ObservationIgnored lazy var routerDispatcher: RouterDispatcher = {
        let dispatcher = RouterDispatcher(store: self)
        dispatcher.claudePath = { [weak self] in self?.routerStatus.claudeCode?.path }
        return dispatcher
    }()
    /// Where the Router's files go, in a test (see `routerFiles`).
    @ObservationIgnored var routerPaths: RouterPaths?
    /// The executable the hook runs; this one unless a test says otherwise.
    @ObservationIgnored var routerExecutable: String?
    /// The latest install or removal of the hook (each waits for the one before).
    @ObservationIgnored var routerHookWork: Task<Void, Never>?
    /// Runs Claude Code's CLI for the plugin; a test stands one in (without one, a test run leaves the plugin alone).
    @ObservationIgnored var routerPluginRunner: ClaudePluginInstaller.Runner?
    /// Who may make the relay key (see `RelayKeyFence`), and the key as last read (see `signRelay`).
    @ObservationIgnored let relayKeyFence = RelayKeyFence()
    @ObservationIgnored var relayKeyCache: RelayKeyCache?
    @ObservationIgnored var pluginQuitObserver: NSObjectProtocol?
    /// Where Claude Code's binary is; the newest copy the Claude app bundles unless a test says otherwise.
    @ObservationIgnored var routerClaudeBinary: (@Sendable () -> String?)?
    /// The app's version, which the plugin's is stamped with.
    @ObservationIgnored var routerAppVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0-dev"
    @ObservationIgnored let activityReader = Claude.ActivityReader()
    @ObservationIgnored lazy var claudeFeed = ClaudeFeed(activityReader: activityReader)
    /// Derived rows, rebuilt after any change to the agents or what was read (see Agents.swift).
    @ObservationIgnored var agentCache: AgentCache?
    /// Tells a read of the app that was asked for before you changed something from one asked for after.
    @ObservationIgnored var claudeStamp = ClaudeStamp()
    @ObservationIgnored var ingesting = false
    @ObservationIgnored var iconTask: Task<Void, Never>?
    /// Sessions you asked an icon for, picked before the rest (they may not be listed).
    @ObservationIgnored var iconRequests: [String] = []
    /// Sessions with nothing to go on yet (see `iconStamp` for when they're looked at again).
    @ObservationIgnored var iconDeferred: [String: String] = [:]
    @ObservationIgnored var iconsPausedUntil = Date.distantPast
    /// Where icons get their input and their answer (a session's first message by transcript id; Jev's choice from
    /// options, hints, state and instructions). Tests swap them for the disk and the network.
    @ObservationIgnored var iconFirstMessage: (@Sendable (String) -> String?)?
    @ObservationIgnored var iconChooser: (([String], [String: String], [String: String], String) async throws -> JevClient.Choice)?
    @ObservationIgnored var typesafeKeyCache: String?
    /// Jev's reading of the inbox (InboxJev.swift): tests answer for TypeSafe. A failed call waits until this.
    @ObservationIgnored var inboxAsker: InboxJev.Asker?
    @ObservationIgnored var inboxJevPausedUntil = Date.distantPast
    /// What keeps a key in the Keychain (tests answer for it).
    @ObservationIgnored var keychainWrite: ((String, String) -> Bool)?
    @ObservationIgnored private var transcriptWatcher: FolderWatcher?
    @ObservationIgnored private var sessionsWatcher: FolderWatcher?
    @ObservationIgnored private var dotsWatcher: FolderWatcher?
    @ObservationIgnored var claudeTimer: Timer?
    @ObservationIgnored private var claudeObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var screensAsleep = false

    private nonisolated static func isClaude(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Claude.bundleID
    }

    /// Where the state is kept, when not in the user's own file: a test's, in a folder of its own. A test run that reaches the
    /// user's file stops (see `UnderTest`).
    @ObservationIgnored var stateFile: URL?

    /// Where the state file is (its neighbours live beside it).
    var stateFileURL: URL? { file }

    /// The file the state is read from and written to; nil when a test has not said where, and was stopped for it.
    private var file: URL? {
        if let stateFile { return stateFile }
        return UnderTest.refuses("the saved state (Application Support/Lookout/state.json)") ? nil : Self.fileURL
    }

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lookout", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    // MARK: Lifecycle

    func start() {
        load()
        notifier.onOpen = { [weak self] id, url in self?.openNotification(id: id, url: url) }
        notifier.setup()
        updater.automatic = { [weak self] in self?.settings.checkUpdates ?? true }
        updater.skipped = { [weak self] in self?.settings.skippedVersion }
        updater.onSkip = { [weak self] in self?.settings.skippedVersion = $0 }
        updater.start()
        observeSleep()
        restartPolling()
        // The Router is the only reader of Claude's sessions, and they have no switch of their own: they follow it.
        if agents.enabled != router.enabled {
            agents.enabled = router.enabled
            if router.enabled { agents.enabledAt = agents.enabledAt ?? Date() }
        }
        watchClaude()
        startRouter()
        Task.detached(priority: .utility) {
            let key = Keychain.read(Keychain.typesafe) ?? ""
            await MainActor.run { [weak self] in
                // A key saved meanwhile (Settings) is newer than this read.
                guard let self, self.typesafeKeyCache == nil else { return }
                self.typesafeKeyCache = key
                self.hasTypesafeKey = !key.isEmpty
                self.pickIcons()
            }
        }
    }

    /// File events give near-instant updates: the sessions folder triggers a read of the sessions, the app's local
    /// storage (where it lazily writes the sidebar dots) only a re-read of the dots. What events can't tell is covered
    /// by the app launching, quitting or coming to the front, and by a one-shot timer (see `scheduleClaudeTick`).
    func watchClaude() {
        sessionsWatcher = nil
        dotsWatcher = nil
        transcriptWatcher = nil
        claudeTimer?.invalidate()
        claudeTimer = nil
        claudeDeadline = nil
        let center = NSWorkspace.shared.notificationCenter
        claudeObservers.forEach { center.removeObserver($0) }
        claudeObservers = []
        guard agents.enabled else { return }
        sessionsWatcher = FolderWatcher([Claude.sessionsDir]) { [weak self] in
            MainActor.assumeIsolated { self?.refreshClaude() }
        }
        // The app writes to its leveldb in bursts: one read of the dots per couple of seconds is plenty.
        dotsWatcher = FolderWatcher([Claude.localStorageDir], latency: 2) { [weak self] in
            MainActor.assumeIsolated { self?.refreshUnread() }
        }
        // Transcripts change with every step an agent takes: only the working sessions' tails are read, and only the
        // transcripts of working sessions (and those with background tasks) are worth waking up for. The filter runs
        // on the watcher's queue; `isRelevant` takes its own lock.
        let feed = claudeFeed
        transcriptWatcher = FolderWatcher([Claude.transcriptsDir], latency: 0.5, relevant: { feed.isRelevant($0) }) { [weak self] in
            MainActor.assumeIsolated { self?.refreshActivity() }
        }
        func watch(_ name: Notification.Name, _ then: @escaping @MainActor (Store) -> Void) {
            claudeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard Self.isClaude(note) else { return }
                MainActor.assumeIsolated { if let self { then(self) } }
            })
        }
        // Whether the app is open decides if a session still "runs"; being in front, which one you're looking at.
        watch(NSWorkspace.didLaunchApplicationNotification) { $0.refreshClaude() }
        watch(NSWorkspace.didTerminateApplicationNotification) { $0.refreshClaude() }
        watch(NSWorkspace.didActivateApplicationNotification) { $0.refreshClaude() }
        claudeObservers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = true
                self?.claudeTimer?.invalidate()
                self?.claudeTimer = nil
                self?.claudeDeadline = nil
            }
        })
        claudeObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.screensAsleep = false
                self.refreshClaude()
            }
        })
        screensAsleep = false
        refreshClaude()
    }

    /// How soon to read again because a session's background work isn't known yet (see `RouterFeed.update`): only while the
    /// Router waits on a finished turn of a session that isn't running and the last read couldn't say. Nil otherwise (no tick
    /// for it at rest).
    var inventoryRecheck: TimeInterval? {
        guard router.enabled, let inventory = claudeTaskInventory else { return nil }
        let waiting = router.pendingTurns.keys.contains { id in
            claudeSessions[id].map { !$0.running && !inventory.contains(id) } ?? false
        }
        return waiting ? Self.inventoryRecheckDelay : nil
    }

    /// Past the five seconds a command just listed has to show up open (see `Claude.TaskReader.read`).
    nonisolated static let inventoryRecheckDelay: TimeInterval = 5

    /// What nothing announces is the clock: a turn with no summary stops counting as running two hours after its last
    /// message, and a background subagent that stopped writing is given up on. One timer, set after each read for the
    /// first moment something can expire (and none while the screens are asleep or nothing is running).
    func scheduleClaudeTick() {
        guard agents.enabled, persists, !screensAsleep else {
            claudeTimer?.invalidate()
            claudeTimer = nil
            claudeDeadline = nil
            return
        }
        var next: TimeInterval?
        let now = Date()
        for session in claudeSessions.values where session.running {
            let left = (session.lastUserMessage ?? .distantPast).addingTimeInterval(Claude.runningTimeout).timeIntervalSince(now)
            next = min(next ?? left, left)
        }
        // Sessions with background work: its end isn't always an event (a command's process just exits).
        if !claudeTasks.isEmpty { next = min(next ?? 60, 60) }
        // A finished turn the Router waits to card while what it left running isn't known yet: read again soon (past the
        // grace a just-listed command gets), until it is.
        if let recheck = inventoryRecheck { next = min(next ?? recheck, recheck) }
        // Icon picking waits out a failure (a rejected key waits for a new one instead).
        if agents.iconsEnabled, iconsPausedUntil > now, iconsPausedUntil < .distantFuture {
            next = min(next ?? .infinity, iconsPausedUntil.timeIntervalSince(now))
        }
        guard let next else { return }
        let deadline = now.addingTimeInterval(max(next, 1) + 1)
        // Frequent reads must not keep pushing it back: it only moves earlier.
        if claudeTimer?.isValid == true, let current = claudeDeadline, current <= deadline { return }
        claudeTimer?.invalidate()
        claudeDeadline = deadline
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.claudeDeadline = nil
                self?.refreshClaude()
            }
        }
        timer.tolerance = max(next, 1) * 0.1 + 2
        RunLoop.main.add(timer, forMode: .common)
        claudeTimer = timer
    }

    func restartPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.systemAsleep { await self.pollAll() }
                await self.sleepUntilNextPoll()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        sleeper?.cancel()
    }

    func refreshNow() {
        authRetry = true
        // Asked for during a poll: that one may be on its way out with what it knew before, so one more follows it.
        if isSyncing { refreshQueued = true } else { Task { await pollAll() } }
    }

    /// The hub being open means someone is looking: sync now if stale, and poll faster meanwhile.
    func setHubOpen(_ open: Bool) {
        guard open != hubOpen else { return }
        hubOpen = open
        sleeper?.cancel()
        guard open, !isSyncing else { return }
        // Signed out for want of a token, `gh auth login` may have been run since: look again, however recent the last poll.
        if awaitsToken || Date().timeIntervalSince(lastSync ?? .distantPast) > 60 { refreshNow() }
    }

    /// Signed out with no token to ask GitHub about: the only case where a look for one (it reads the Keychain and may run
    /// `gh`) is likely to find something new, once the user has signed in elsewhere.
    private var awaitsToken: Bool { me == nil && gh.token == nil && authError != nil }

    /// `gh auth login` was run in Terminal, which the app comes back from: the look the polls hold back (see `authBackoff`)
    /// is made now. Nothing happens for any other reason to be signed out.
    func appBecameActive() {
        if awaitsToken, !isSyncing { refreshNow() }
    }

    /// How often to poll: the setting, at most 30 s while the hub is open, and doubled in Low Power Mode whichever it is.
    private var effectivePollInterval: TimeInterval {
        let base = settings.pollInterval
        return (hubOpen ? min(base, 30) : base) * (ProcessInfo.processInfo.isLowPowerModeEnabled ? 2 : 1)
    }

    /// Sleeps in slices so a change (hub opening, wake, new interval) can cut it short.
    private func sleepUntilNextPoll() async {
        while !Task.isCancelled {
            if pollNow, !systemAsleep {
                pollNow = false
                return
            }
            var wait = 3600.0
            if !systemAsleep {
                wait = effectivePollInterval - Date().timeIntervalSince(lastSync ?? .distantPast)
                // Out of calls: nothing is sent before the reset, so that is when to check again, whatever is left of the interval.
                if rateRemaining == 0, let reset = rateResetsAt {
                    if reset <= Date(), (lastSync ?? .distantPast) < reset, !isSyncing { return }
                    if reset > Date() { wait = min(wait, reset.timeIntervalSinceNow) }
                }
                if wait <= 0 {
                    if !isSyncing { return }
                    wait = 1
                }
            }
            let seconds = wait
            let task = Task<Void, Never> { try? await Task.sleep(for: .seconds(seconds)) }
            sleeper = task
            sleeperWakes = Date(timeIntervalSinceNow: seconds)
            await task.value
            // Over: nothing is asleep until the next one (unless another sleep has taken its place meanwhile).
            if sleeper == task {
                sleeper = nil
                sleeperWakes = nil
            }
        }
    }

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemAsleep = true }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.systemAsleep = false
                    self.pollNow = true
                    self.sleeper?.cancel()
                }
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appBecameActive() }
            },
        ]
    }

    // MARK: Persistence

    func load() {
        loading = true
        defer { loading = false }
        guard let file, let data = try? Data(contentsOf: file) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let state = try? dec.decode(PersistedState.self, from: data) else { return }
        settings = state.settings
        agents = state.agents ?? AgentsState()
        router = state.router ?? RouterState()
        changingInbox(.load) {
            if let c = state.categories { categories = c }
            groups = state.groups ?? []
        }
        things = state.things ?? [:]
        marks = state.marks ?? [:]
        categoryBaselines = state.categoryBaselines ?? [:]
        ownedRepos = state.ownedRepos ?? []
        contributedRepos = state.contributedRepos ?? []
        myTeams = state.myTeams ?? []
        reposResolvedAt = state.reposResolvedAt
        login = state.login ?? ""
        savedRevision = persistedRevision
        loadActions()
    }

    private static let writer = DispatchQueue(label: "lookout.save")

    /// Coalesced: the write happens shortly after the last call, off the main thread.
    func save() {
        // (Asked now, not when the write comes: a test that reaches the user's file is stopped where it did.)
        guard persists, !loading, file != nil else { return }
        savedRevision = persistedRevision
        saveDirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.writeSnapshot(wait: false)
        }
    }

    /// Writes any pending change now (quitting).
    func flushSave() {
        saveTask?.cancel()
        writeSnapshot(wait: true)
    }

    private func writeSnapshot(wait: Bool) {
        guard saveDirty, persists, !loading else {
            if wait { Self.writer.sync {} }
            return
        }
        guard let url = file else { return }
        saveDirty = false
        let box = SnapshotBox(state: PersistedState(settings: settings, agents: agents, router: router, categories: categories,
                                                       groups: groups, things: things, marks: marks,
                                                       categoryBaselines: categoryBaselines, ownedRepos: ownedRepos,
                                                       contributedRepos: contributedRepos, reposResolvedAt: reposResolvedAt,
                                                       myTeams: myTeams, login: login.isEmpty ? nil : login))
        let write: @Sendable () -> Void = {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            if let data = try? enc.encode(box.state) {
                try? data.write(to: url, options: .atomic)
            }
        }
        if wait { Self.writer.sync(execute: write) } else { Self.writer.async(execute: write) }
    }

    private struct SnapshotBox: @unchecked Sendable { let state: PersistedState }

    // MARK: Derived

    /// Whether notifications are snoozed. The views that read it are redrawn once, when the snooze runs out (`snoozeRevision`):
    /// nothing changes in the settings then, and nothing ticks for it.
    var isSnoozed: Bool {
        _ = snoozeRevision
        return (settings.snoozeUntil ?? .distantPast) > Date()
    }

    /// Bumped when a snooze's deadline passes.
    private var snoozeRevision = 0
    @ObservationIgnored private var snoozeExpiry: (deadline: Date, task: Task<Void, Never>)?

    /// One cancellable one-shot at the snooze's deadline, kept in step with the setting.
    private func armSnoozeExpiry() {
        guard let until = settings.snoozeUntil, until > Date() else {
            snoozeExpiry?.task.cancel()
            snoozeExpiry = nil
            return
        }
        guard snoozeExpiry?.deadline != until else { return }
        snoozeExpiry?.task.cancel()
        snoozeExpiry = (until, Task { [weak self] in
            try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow))
            guard !Task.isCancelled, let self else { return }
            snoozeRevision &+= 1
            snoozeExpiry = nil
        })
    }

    // MARK: Notification clicks

    /// A clicked banner: `inbox:<thing id>` opens the thing's category with it selected, a summary opens the inbox, and
    /// anything else the page it was about.
    func openNotification(id: String, url: String?) {
        if id.hasPrefix(Self.inboxNotificationPrefix) {
            let thing = String(id.dropFirst(Self.inboxNotificationPrefix.count))
            if let entry = entries.first(where: { $0.id == thing }) {
                onOpenInbox?(entry.categoryID, thing)
                return
            }
        } else if id.hasPrefix(Notifier.summaryPrefix) {
            onOpenInbox?(nil, nil)
            return
        }
        if let url = [url, id].lazy.compactMap({ $0.flatMap { URL(string: $0) } }).first(where: { $0.scheme == "https" }) {
            // The thing is gone (closed, or no rule holds it): the page it was about still makes sense.
            Link.open(url)
        }
    }

    /// Notification ids of inbox things: `inbox:<thing id>`.
    nonisolated static let inboxNotificationPrefix = "inbox:"

    /// Playground: report what would open instead of opening it.
    @ObservationIgnored var interceptOpen: ((String) -> Void)?
    /// Where this store's own announcements go (VoiceOver, through `Announce`): a test listens to its store alone here,
    /// so what other stores say meanwhile (other tests running beside it) never reaches it.
    @ObservationIgnored var announce: (_ text: String, _ again: Bool) -> Void = { Announce.say($0, again: $1) }

    func shortcut(_ action: ShortcutAction) -> Shortcut {
        settings.shortcuts?[action.rawValue] ?? action.defaultShortcut
    }

    /// A stored system-wide shortcut that another app held when Lookout tried to register it.
    func isShortcutHeldByAnotherApp(_ action: ShortcutAction) -> Bool {
        refusedShortcuts[action].map { $0 == shortcut(action) } ?? false
    }

    /// `nil` resets to the default. A global one the system refuses (another app holds the key) is not kept: the one that
    /// works stays stored and registered, and the refusal is returned.
    @discardableResult
    func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) -> ShortcutRefusal? {
        var all = settings.shortcuts ?? [:]
        all[action.rawValue] = shortcut == action.defaultShortcut ? nil : shortcut
        let wanted = all[action.rawValue] ?? action.defaultShortcut
        if action.isGlobal, onGlobalShortcutChange?(action, wanted) == false { return .unavailable(wanted) }
        settings.shortcuts = all.isEmpty ? nil : all
        return nil
    }

    /// Asks the system again for the stored system-wide key another app held, which it may have let go of since.
    func retryShortcut(_ action: ShortcutAction) -> Bool {
        !action.isGlobal || onGlobalShortcutChange?(action, shortcut(action)) != false
    }

    /// A recorder starts listening; one that already was is stopped, so only one ever is.
    func beginRecordingShortcut(stop: @escaping () -> Void) {
        stopRecorder?()
        stopRecorder = stop
        onRecordingShortcutChange?(true)
    }

    func endRecordingShortcut() {
        stopRecorder = nil
        onRecordingShortcutChange?(false)
    }

    func snooze(for seconds: TimeInterval?) {
        settings.snoozeUntil = seconds.map { Date().addingTimeInterval($0) }
    }

    func snoozeUntilTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        settings.snoozeUntil = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
    }

    // MARK: Auth

    /// Signs in with the token held, else the one `resolveToken` finds. A token already held is asked about as it is: finding one
    /// reads the Keychain and may run `gh`, which a poll that fails (offline, a VPN down, GitHub's own trouble) would do every
    /// minute. Only no token, one GitHub refused (`dropRejectedToken`), or a change in Settings (`setToken`) looks again.
    func authenticate() async {
        // What Settings changes while this waits (on the token found, or on /user) is about another token: nothing of it is kept.
        let asked = credentialsChanged
        if gh.token == nil || foundAt != credentialsChanged {
            lastAuthAttempt = Date()
            let find = resolveToken
            let resolved = await Task.detached(operation: find).value
            guard asked == credentialsChanged else { return }
            guard let (token, source) = resolved else {
                gh.token = nil
                me = nil
                tokenSource = nil
                unreachable = false
                signInFailed("No GitHub token found. Run `gh auth login`, or paste a token in Settings.")
                return
            }
            gh.token = token
            tokenSource = source
            foundAt = asked
        }
        do {
            let user = try await gh.get("/user", as: GHUser.self)
            guard asked == credentialsChanged else { return }
            me = user
            authError = nil
            awaitingSignIn = false
            unreachable = false
        } catch {
            guard asked == credentialsChanged else { return }
            if error is URLError {
                // Only a missing or refused token is a sign-in problem: an earlier one is not this attempt's.
                authError = nil
                unreachable = true
                return
            }
            me = nil
            unreachable = false
            signInFailed(error.localizedDescription)
        }
    }

    /// Sets the sign-in problem. The editor in Settings closes once the Keychain has a token, before GitHub answers, so the
    /// refusal of what was just saved is said too, once; a later poll's is only shown.
    private func signInFailed(_ reason: String) {
        authError = reason
        guard awaitingSignIn else { return }
        awaitingSignIn = false
        announce(reason, true)
    }

    /// Revoked or expired: forget the token and who it was, so the next look resolves one again
    /// (the user may have run `gh auth login` meanwhile).
    private func dropRejectedToken() {
        gh.token = nil
        me = nil
        tokenSource = nil
        lastAuthAttempt = nil
        authError = "GitHub rejected the token. Run `gh auth login` again, then Retry."
    }

    /// Keeps `token` in the Keychain, or removes it with nothing, and signs in again with what is there. False when the
    /// Keychain refused it: nothing changes then, and the token that was saved before still signs in.
    @discardableResult
    func setToken(_ token: String?) -> Bool {
        if let token, !token.isEmpty {
            guard (keychainWrite ?? Keychain.write)(token, Keychain.github) else { return false }
        } else {
            Keychain.delete()
        }
        me = nil
        awaitingSignIn = true
        credentialsChanged += 1
        refreshNow()
        return true
    }

    // MARK: Repos

    func loadSuggestions() async {
        guard suggestions.isEmpty else { return }
        if me == nil { await authenticate() }
        var names: [String] = []
        if let involved: GHSearch<GHIssue> = try? await gh.get("/search/issues", ["q": "involves:@me", "sort": "updated", "per_page": "100"]) {
            names += involved.items.compactMap { $0.repositoryUrl.map { repoName(from: $0) } }
        }
        if let mine: [GHRepo] = try? await gh.get("/user/repos", ["sort": "pushed", "per_page": "100", "affiliation": "owner,collaborator,organization_member"]) {
            names += mine.map(\.fullName)
        }
        var seen = Set(things.values.map { $0.repo.lowercased() })
        suggestions = names.filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: Polling

    func pollAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            lastSync = Date()
            if rateRemaining != gh.rateRemaining { rateRemaining = gh.rateRemaining }
            rateResetsAt = gh.rateResetsAt
            // A reset learned now (a refresh by hand) may come before the wake the sleeper was set for: it sets that again. One
            // already passed by the time this poll is over (a slow poll) means the calls are back: the loop checks now, once
            // for that reset.
            if gh.rateRemaining == 0, let reset = rateResetsAt, let wakes = sleeperWakes, reset < wakes {
                if reset > Date() {
                    sleeper?.cancel()
                } else if retriedReset != reset {
                    retriedReset = reset
                    pollNow = true
                    sleeper?.cancel()
                }
            }
            if persistedRevision != savedRevision { save() }
            if refreshQueued {
                refreshQueued = false
                Task { await pollAll() }
            }
        }
        // Signed out: look for a token when asked (Retry, a refresh) or once the backoff has passed. One already held is
        // asked about at every poll: that is a request, not a look in the Keychain and `gh`.
        let asked = authRetry
        authRetry = false
        // A 401 from outside a poll (adding a repo, suggestions) left the token and who it was cached.
        if gh.tokenRejected { dropRejectedToken() }
        if me == nil, asked || gh.token != nil || Date().timeIntervalSince(lastAuthAttempt ?? .distantPast) >= Self.authBackoff {
            await authenticate()
        }
        guard me != nil else { return }
        defer { if gh.tokenRejected { dropRejectedToken() } }
        await syncInbox()
    }

    /// Asks GitHub for the CI of a repo's default branch (found once, then remembered), and the commit's headline.
    func fetchCI(_ name: String) async throws -> CIStatus {
        var branch = defaultBranches[name]
        if branch == nil {
            let info: GHRepo = try await gh.get("/repos/\(name)")
            defaultBranches[name] = info.defaultBranch
            branch = info.defaultBranch
        }
        return try await fetchBranchCI(name, branch: branch!)
    }

    /// Asks GitHub for the CI of one branch of a repo, and the commit's headline.
    func fetchBranchCI(_ name: String, branch: String) async throws -> CIStatus {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let ref = branch.addingPercentEncoding(withAllowedCharacters: allowed) ?? branch
        // Only push-triggered Actions runs count: issue/comment-triggered workflows also run against the
        // default branch HEAD and would otherwise make CI look red.
        let actions: GHWorkflowRuns = try await gh.get("/repos/\(name)/actions/runs",
                                                       ["branch": branch, "event": "push", "per_page": "30"])
        let sha = actions.workflowRuns.first?.headSha
        let target = sha ?? ref
        async let checksReq: GHCheckRuns = gh.get("/repos/\(name)/commits/\(target)/check-runs", ["per_page": "100"])
        async let statusReq: GHCombinedStatus = gh.get("/repos/\(name)/commits/\(target)/status")
        let (checks, combined) = try await (checksReq, statusReq)
        let reading = Self.readCI(runs: actions.workflowRuns, sha: sha, checks: checks.checkRuns, combined: combined)
        let commit = sha ?? combined.sha
        // The headline comes from the Actions run; a repo with only external CI asks the commit for it (once per commit).
        let title = await ciHeadline(name, commit: commit, runTitle: actions.workflowRuns.first?.displayTitle)
        return CIStatus(branch: branch, sha: commit, url: URL(string: "https://github.com/\(name)/commit/\(commit)"),
                        checkedAt: Date(), title: title, updatedAt: reading.changedAt, workflows: reading.workflows)
    }

    /// What CI's three sources say about one commit.
    struct CIReading: Equatable {
        /// The latest change among them: an Actions run, an external check run or a legacy status.
        var changedAt: Date?
        /// Each workflow's state and failed jobs (the external checks and legacy statuses together are one more, `external`).
        var workflows: [CIStatus.Workflow] = []
    }

    /// The id of the one workflow that stands for external check runs and legacy statuses.
    nonisolated static let externalWorkflowID = "external"

    /// Folds Actions runs (the latest of each workflow, on `sha`) and their jobs, external check runs and legacy statuses
    /// into each workflow's state and failed names, and when any of them last changed. Any of the three can be all a repo
    /// has.
    nonisolated static func readCI(runs: [GHWorkflowRuns.Run], sha: String?, checks: [GHCheckRuns.Run],
                                   combined: GHCombinedStatus) -> CIReading {
        var latest: [Int: GHWorkflowRuns.Run] = [:]
        for run in runs where run.headSha == sha && latest[run.workflowId] == nil { latest[run.workflowId] = run }
        let external = checks.filter { $0.app?.slug != "github-actions" }

        let bad: Set<String> = ["failure", "timed_out", "action_required", "startup_failure"]
        // A failed workflow is named by the jobs that failed in it (each is a check run in the run's own suite); its own
        // name stands in only when none is found. Jobs of runs not chosen above (another trigger) never count.
        let jobs = checks.filter { $0.app?.slug == "github-actions" && bad.contains($0.conclusion ?? "") }
        var workflows: [CIStatus.Workflow] = []
        for run in latest.values.sorted(by: { ($0.name, $0.workflowId) < ($1.name, $1.workflowId) }) {
            var failing: [String] = []
            if bad.contains(run.conclusion ?? "") {
                let failed = jobs.filter { run.checkSuiteId != nil && $0.checkSuite?.id == run.checkSuiteId }.map(\.name)
                failing = failed.isEmpty ? [run.name] : failed
            }
            let state: CIState = !failing.isEmpty ? .failure : run.status != "completed" ? .pending : .success
            workflows.append(CIStatus.Workflow(id: "\(run.workflowId)", name: run.name, state: state, failing: failing,
                                               url: run.htmlUrl, updatedAt: run.updatedAt))
        }
        if !external.isEmpty || combined.totalCount > 0 {
            let failing = external.filter { bad.contains($0.conclusion ?? "") }.map(\.name)
                + combined.statuses.filter { $0.state == "failure" || $0.state == "error" }.map(\.context)
            let pending = external.contains { $0.status != "completed" } || combined.statuses.contains { $0.state == "pending" }
            let changed = external.compactMap { $0.completedAt ?? $0.startedAt }
                + combined.statuses.compactMap { $0.updatedAt ?? $0.createdAt }
            workflows.append(CIStatus.Workflow(id: externalWorkflowID, name: "Checks",
                                               state: !failing.isEmpty ? .failure : pending ? .pending : .success,
                                               failing: failing, url: nil, updatedAt: changed.max()))
        }
        return CIReading(changedAt: workflows.compactMap(\.updatedAt).max(), workflows: workflows)
    }

    /// The commit's headline: the Actions run's title when there is one; else what the commit says, asked once per
    /// commit (a repo with only external CI has no run to read it from).
    func ciHeadline(_ name: String, commit: String, runTitle: String?) async -> String? {
        if let runTitle { return runTitle }
        if let known = headlines[name], known.commit == commit { return known.title }
        let found: GHCommit? = try? await gh.get("/repos/\(name)/commits/\(commit)")
        if let title = found?.headline { headlines[name] = (commit, title) }
        return found?.headline
    }

    // MARK: Notifications

    func notify(id: String, title: String, subtitle: String, body: String, quiet: Bool, url: URL? = nil) {
        guard settings.notifications, !isSnoozed else { return }
        notifier.post(id: id, title: title, subtitle: subtitle, body: body, quiet: quiet, url: url)
    }

    // MARK: Helpers

    private func repoName(from url: URL) -> String {
        url.pathComponents.suffix(2).joined(separator: "/")
    }
}
