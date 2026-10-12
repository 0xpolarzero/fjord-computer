import AppKit
import SwiftUI

// MARK: - Looking through the folders

/// Your code folders (Settings › Code folders): the folders you keep your clones in, looked through for git repos and the
/// GitHub repos their remotes name, so every clone on this Mac is known, not only those a Claude session ran in. Only each
/// repo's `.git` is read (its config, and where a worktree's points); no `git` is run.
enum CodeFolders {
    /// How far below a code folder repos are looked for: from `~/code`, one at `~/code/a/b/c/repo` is found.
    static let maxDepth = 4
    /// At most this many folders are looked into per scan: a code folder too big to look through whole is cut short, not slow.
    static let maxFolders = 20_000
    /// Folders never looked into: what builds, package managers and virtual environments fill, where no clone of yours is.
    /// Hidden ones (`.build`, `.venv`…) are skipped as hidden, and named here all the same.
    static let skipped: Set<String> = [
        "node_modules", "bower_components", ".build", "build", "DerivedData", "Pods", "Carthage", "vendor", "target", "dist",
        ".venv", "venv", "__pycache__", ".tox", ".gradle", ".next", ".nuxt", "zig-cache", "zig-out", ".zig-cache",
        // A bare repo's insides (`objects` alone has 256 folders), should one not be recognised as such.
        "objects", "refs",
    ]
    /// Folders of your home the system guards (reading them asks you first), and the Library, which is huge and holds no
    /// clone of yours: looked into only when they are, or are in, a code folder you added.
    static let guarded = ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures"]

    /// What a scan found.
    struct Found: Equatable, Sendable {
        /// Every repo, by its folder: the GitHub repos its remotes name (`owner/repo`, lowercased, origin's first), empty for
        /// one with none on GitHub.
        var repos: [String: [String]] = [:]
        /// The bare repos and mirrors among `repos` (`foo.git`, no working tree): known, but no clone to work in.
        var bare: Set<String> = []
        /// The scan stopped at `maxFolders`: what it hadn't reached yet isn't in `repos`.
        var cutShort = false
    }

    /// Looks through `roots` breadth first (the shallow folders of every root before the deeper ones, so a cut-short scan
    /// misses the deepest), down to `maxDepth` below each. A folder with a `.git` (a folder, or a file in a worktree) is a
    /// repo and isn't looked into, and so is a bare one; hidden folders, symlinks, packages, `skipped` and `guarded` ones are
    /// passed over. Each root is looked through where it really is (`~/code` linked to `/Volumes/Data/code` is keyed under
    /// the latter), as a session's folder is the one it really ran in.
    nonisolated static func scan(roots: [String], maxDepth: Int = maxDepth, maxFolders: Int = maxFolders,
                                 home: String = NSHomeDirectory()) -> Found {
        let fm = FileManager.default
        let guardedPaths = Set(guarded.map { (resolved(home) as NSString).appendingPathComponent($0) })
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        var found = Found()
        var seen = Set<String>()
        var queue = roots.map { (resolved($0), 0) }
        var next = 0
        while next < queue.count {
            let (folder, depth) = queue[next]
            next += 1
            guard seen.insert(folder).inserted else { continue }
            guard seen.count <= maxFolders else { found.cutShort = true; break }
            let bare = isBare(folder)
            if bare || isRepo(folder) {
                found.repos[folder] = remotes(of: folder)
                if bare { found.bare.insert(folder) }
                continue
            }
            guard depth < maxDepth,
                  let children = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: folder, isDirectory: true),
                                                             includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            else { continue }
            for child in children {
                let name = child.lastPathComponent
                guard !name.hasPrefix("."), !skipped.contains(name),
                      let values = try? child.resourceValues(forKeys: Set(keys)),
                      values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true else { continue }
                let path = (folder as NSString).appendingPathComponent(name)
                guard !guardedPaths.contains(path) else { continue }
                queue.append((path, depth + 1))
            }
        }
        return found
    }

    /// A path as the scan keys it: `~` expanded, no trailing slash.
    nonisolated static func normalized(_ path: String) -> String {
        var path = (path as NSString).expandingTildeInPath
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// A path where it really is: `normalized`, then its links resolved (`/var` is `/private/var`); as it was given when it
    /// can't be resolved (it isn't there).
    nonisolated static func resolved(_ path: String) -> String {
        let given = normalized(path)
        guard let real = realpath(given, nil) else { return given }
        defer { free(real) }
        return String(cString: real)
    }

    /// Whether a folder is a bare repo or a mirror (`git clone --bare`): no `.git`, its own `HEAD`, `config`, `objects` and
    /// `refs`.
    nonisolated static func isBare(_ folder: String) -> Bool {
        let fm = FileManager.default
        func has(_ name: String, folder wanted: Bool) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: (folder as NSString).appendingPathComponent(name), isDirectory: &isDir) && isDir.boolValue == wanted
        }
        return !isRepo(folder) && has("HEAD", folder: false) && has("config", folder: false) && has("objects", folder: true)
            && has("refs", folder: true)
    }

    /// Whether a folder is a repo's own (its `.git` is there, a folder or a worktree's file); a folder inside one isn't.
    nonisolated static func isRepo(_ folder: String) -> Bool {
        FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent(".git"))
    }

    /// The GitHub repos a repo's remotes name (origin's first); none for a folder that isn't a repo's own.
    nonisolated static func remotes(of folder: String) -> [String] {
        guard let dir = configDir(of: folder),
              let config = try? String(contentsOfFile: (dir as NSString).appendingPathComponent("config"), encoding: .utf8)
        else { return [] }
        return remotes(config: config)
    }

    /// Where a repo's config is. In a worktree (or a submodule) `.git` is a file, `gitdir: <path>`, relative to the folder
    /// or not; that git dir's `commondir`, when it has one (a worktree's does), is where the shared config is. A bare repo's is
    /// itself.
    nonisolated static func configDir(of folder: String) -> String? {
        let dotGit = (folder as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDir) else { return isBare(folder) ? folder : nil }
        guard !isDir.boolValue else { return dotGit }
        guard let text = try? String(contentsOfFile: dotGit, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let gitDir = resolve(line.dropFirst(7).trimmingCharacters(in: .whitespaces), from: folder)
        guard let common = try? String(contentsOfFile: (gitDir as NSString).appendingPathComponent("commondir"), encoding: .utf8)
        else { return gitDir }
        let trimmed = common.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? gitDir : resolve(trimmed, from: gitDir)
    }

    private nonisolated static func resolve(_ path: String, from base: String) -> String {
        let joined = path.hasPrefix("/") ? path : (base as NSString).appendingPathComponent(path)
        return (joined as NSString).standardizingPath
    }

    /// The GitHub repos a git config's remotes name: each `url` of each `[remote "…"]` section, origin's first, once each.
    nonisolated static func remotes(config: String) -> [String] {
        var remote: String?
        var found: [(remote: String, repo: String)] = []
        for raw in config.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                // `[remote "origin"]`: the section's name, and its subsection between quotes.
                let header = line.dropFirst().prefix { $0 != "]" }
                let parts = header.split(separator: " ", maxSplits: 1)
                remote = parts.first?.lowercased() == "remote" && parts.count == 2
                    ? parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) : nil
                continue
            }
            guard let name = remote, let eq = line.firstIndex(of: "="),
                  line[..<eq].trimmingCharacters(in: .whitespaces).lowercased() == "url" else { continue }
            let value = line[line.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
            if let repo = LocalClones.repo(fromRemote: value) { found.append((name, repo)) }
        }
        var repos: [String] = []
        for (_, repo) in found.filter({ $0.remote == "origin" }) + found.filter({ $0.remote != "origin" }) where !repos.contains(repo) {
            repos.append(repo)
        }
        return repos
    }

    /// Folders in the order the Router lists projects: by name, then path; Scratch ("") last.
    nonisolated static func sorted(_ folders: Set<String>) -> [String] {
        // The names to sort by are taken once each, not on every comparison.
        let keyed = folders.map { ($0, FolderNames.components($0).last?.lowercased() ?? "") }
        return keyed.sorted { a, b in
            if a.0.isEmpty != b.0.isEmpty { return !a.0.isEmpty }
            return a.1 != b.1 ? a.1 < b.1 : a.0 < b.0
        }.map(\.0)
    }
}

// MARK: - Keeping it fresh

/// Keeps what your code folders hold known: looked through at launch, when you change them, when Fjord Computer comes to
/// the front (at most once a minute) and every five minutes, off the main thread. A request made while a scan runs folds
/// into one more scan after it; what reads `repos` is redrawn only when a scan found something else.
///
/// It also keeps the remotes of your sessions' folders (read off the main thread when a folder first shows up, and again
/// with each scan), so the projects and every clone of a repo are known from memory: `projectFolders`, `knows`, `clones(of:)`.
@Observable
@MainActor
final class CodeFolderScanner {
    /// Every repo found (see `CodeFolders.Found.repos`), the bare ones too.
    private(set) var repos: [String: [String]] = [:]
    /// The last scan stopped at `CodeFolders.maxFolders`.
    private(set) var cutShort = false
    /// A scan has ended since launch (until then, Settings says it is looking).
    private(set) var scanned = false
    /// Every project folder: your sessions' and the clones found (not the bare repos), sorted as the Router lists projects,
    /// without Scratch. Worked out again only when either changes.
    private(set) var projectFolders: [String] = []

    /// The clones found (`repos` without the bare ones).
    @ObservationIgnored private(set) var clones: [String: [String]] = [:]
    @ObservationIgnored private var bare: Set<String> = []
    /// `projectFolders` as a set, Scratch ("") in it when a session is in no folder.
    @ObservationIgnored private var projectSet: Set<String> = []
    /// Each repo (`owner/repo`, lowercased) to its clones among the project folders, shortest path first.
    @ObservationIgnored private var clonesByRepo: [String: [String]] = [:]
    /// The sessions' folders as last told (`sessionFoldersChanged`), and the GitHub repos each one's remotes name.
    @ObservationIgnored private var sessionFolders: Set<String> = []
    @ObservationIgnored private var sessionRemotes: [String: [String]] = [:]

    /// How a scan is made, and a folder's remotes read; a test stands them in.
    @ObservationIgnored var scan: @Sendable ([String]) -> CodeFolders.Found = { CodeFolders.scan(roots: $0) }
    @ObservationIgnored var readRemotes: @Sendable (String) -> [String] = { CodeFolders.remotes(of: $0) }
    @ObservationIgnored private weak var store: Store?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var remotesWork: Task<Void, Never>?
    @ObservationIgnored private var again = false
    @ObservationIgnored private var lastScan: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activation: NSObjectProtocol?

    static let interval: TimeInterval = 300
    /// Coming to the front scans again only this long after the last scan.
    static let activationGap: TimeInterval = 60

    init(store: Store) { self.store = store }

    /// The code folders, as Settings holds them.
    private var roots: [String] { store?.settings.codeFolders ?? [] }

    /// Scans now, and from then on every `interval` and when the app comes to the front.
    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let last = self.lastScan, Date().timeIntervalSince(last) < Self.activationGap { return }
                self.refresh()
            }
        }
    }

    /// Asks for a scan: one starts now, or once the one under way ends.
    func refresh() {
        again = true
        guard work == nil else { return }
        work = Task { [weak self] in
            while let self, self.again {
                self.again = false
                await self.scanOnce()
            }
            self?.work = nil
        }
    }

    /// Waits for the scans and reads asked for so far (tests).
    func settled() async {
        while work != nil || remotesWork != nil {
            if let work { await work.value }
            if let remotesWork { await remotesWork.value }
        }
    }

    /// Whether a folder is a project's: a session's (Scratch's "" when a session is in none) or a clone found.
    func knows(_ folder: String) -> Bool { projectSet.contains(folder) }

    /// Every clone of `repo` (`owner/repo`, any case) among the project folders, shortest path first (a checkout before its
    /// worktrees). From memory: nothing is read.
    func clones(of repo: String) -> [String] { clonesByRepo[repo.lowercased()] ?? [] }

    /// The sessions' folders, told whenever they may have changed (`Store.refreshFolderNames`): the projects are worked out
    /// again when they did, and the remotes of a folder not read yet are read, off the main thread.
    func sessionFoldersChanged(_ folders: Set<String>) {
        guard folders != sessionFolders else { return }
        sessionFolders = folders
        rebuild()
        readNewSessionRemotes()
    }

    private func readNewSessionRemotes() {
        guard remotesWork == nil else { return }
        remotesWork = Task { [weak self] in
            // Until every folder told is read: one that came while a read ran is read next.
            while let self {
                let unread = self.sessionFolders.filter { !$0.isEmpty && self.sessionRemotes[$0] == nil && self.clones[$0] == nil }
                guard !unread.isEmpty else { break }
                let read = self.readRemotes
                let found = await OffMain.run { Dictionary(uniqueKeysWithValues: unread.map { ($0, read($0)) }) }
                self.sessionRemotes.merge(found) { _, new in new }
                self.rebuild()
            }
            self?.remotesWork = nil
        }
    }

    private func scanOnce() async {
        let roots = self.roots
        let sessions = sessionFolders.subtracting([""])
        lastScan = Date()
        let (scan, read) = (self.scan, self.readRemotes)
        // The sessions' folders are read again with each scan: a remote added since (a fork's upstream) is taken in.
        let (found, sessionsRead) = await OffMain.run {
            (roots.isEmpty ? CodeFolders.Found() : scan(roots), Dictionary(uniqueKeysWithValues: sessions.map { ($0, read($0)) }))
        }
        sessionRemotes = sessionRemotes.filter { sessionFolders.contains($0.key) }.merging(sessionsRead) { _, new in new }
        // The folders changed while it ran: what it found is old, and the change has asked for another scan.
        guard roots == self.roots else { rebuild(); return }
        let reposChanged = found.repos != repos || found.bare != bare
        if found.repos != repos { repos = found.repos }
        bare = found.bare
        rebuild()
        if reposChanged { store?.refreshFolderNames() }
        if found.cutShort != cutShort { cutShort = found.cutShort }
        if !scanned { scanned = true }
    }

    /// Works out the projects and the clones of each repo again from the sessions' folders and the repos found.
    private func rebuild() {
        clones = repos.filter { !bare.contains($0.key) }
        projectSet = sessionFolders.union(clones.keys)
        let list = CodeFolders.sorted(projectSet.subtracting([""]))
        if list != projectFolders { projectFolders = list }
        var byRepo: [String: [String]] = [:]
        for folder in list {
            // What a scan read of a clone is taken over a session's own read: the same file, read later or at once.
            for repo in clones[folder] ?? sessionRemotes[folder] ?? [] { byRepo[repo, default: []].append(folder) }
        }
        clonesByRepo = byRepo.mapValues { $0.sorted { ($0.count, $0) < ($1.count, $1) } }
    }
}

// MARK: - The Store's side

extension Store {
    /// The code folders you added, as Settings lists them.
    var codeFolderRoots: [String] { settings.codeFolders ?? [] }

    func addCodeFolders(_ paths: [String]) {
        var roots = codeFolderRoots
        for path in paths.map(CodeFolders.normalized) where !path.isEmpty && !roots.contains(path) { roots.append(path) }
        guard roots != codeFolderRoots else { return }
        settings.codeFolders = roots
        codeFolders.refresh()
    }

    func removeCodeFolder(_ path: String) {
        let roots = codeFolderRoots.filter { $0 != path }
        guard roots != codeFolderRoots else { return }
        settings.codeFolders = roots.isEmpty ? nil : roots
        codeFolders.refresh()
    }

    /// Every repo your code folders hold: its folder to the GitHub repos its remotes name (`owner/repo`, lowercased, origin's
    /// first; empty for one with none on GitHub). The bare ones too.
    var codeRepos: [String: [String]] { codeFolders.repos }

    /// Every project folder known: those of your Claude sessions and the clones in your code folders, sorted as the Router
    /// lists projects (no Scratch); kept, not worked out per read. What `@` offers and where a repo's clones are looked for;
    /// the Router's own destinations stay `knownFolders`.
    var projectFolders: [String] { codeFolders.projectFolders }

    /// Whether a folder is a known project's (`projectFolders`, or Scratch's "" when a session is in none).
    func isProjectFolder(_ folder: String) -> Bool { codeFolders.knows(folder) }

    /// Every local clone of `repo` (`owner/repo`, any case), shortest path first: among your sessions' folders and the clones
    /// in your code folders. From memory: their remotes were read off the main thread (see `CodeFolderScanner`).
    func localClones(of repo: String) -> [String] { codeFolders.clones(of: repo) }
}

// MARK: - Settings

/// Settings' Code folders: the folders you keep your clones in (a list with Add and Remove), how many repos they hold, and
/// Rescan.
struct CodeFoldersSettings: View {
    let store: Store

    private var footnote: (CGFloat, CGFloat) { CDS.Density.comfortable.footnote }

    var body: some View {
        let roots = store.codeFolderRoots
        let scanner = store.codeFolders
        SettingsSection("Code folders") {
            SettingsRow("Where your clones are",
                        info: ("Code folders", "Fjord Computer looks through these folders, \(CodeFolders.maxDepth) levels deep, for git clones and the GitHub repos they're of, again every few minutes: @ in the Router can point at any of your projects, and an inbox action can work in any clone of its repo, not only where a Claude session ran. Only each repo's .git is read (its remotes); nothing leaves this Mac. Hidden, build and dependency folders (node_modules, .build…) are skipped, and Desktop, Documents and Downloads are only looked through when you add them, or a folder in them."),
                        below: AnyView(Group {
                            if roots.isEmpty {
                                Text("None").cdsText(footnote, .regular, CDS.Text.secondary)
                            } else {
                                SettingsNest {
                                    ForEach(roots, id: \.self) { root in
                                        let name = Self.name(root)
                                        SettingsRow(name, description: (root as NSString).abbreviatingWithTildeInPath) {
                                            Button("Remove") { store.removeCodeFolder(root) }
                                                .buttonStyle(SettingsButtonStyle(size: .sm))
                                                .accessibilityLabel("Remove \(name)")
                                        }
                                    }
                                }
                            }
                        })) {
                ActionButton("Add folder…") { pick() }
                    .accessibilityLabel("Add a code folder")
                    .accessibilityValue(roots.isEmpty ? "None" : plural(roots.count, "folder"))
            }
            if !roots.isEmpty {
                SettingsDivider()
                SettingsRow("Repos found", description: Self.status(scanner, roots: roots.count),
                            descriptionColor: scanner.cutShort ? CDS.Text.warning : CDS.Text.muted) {
                    ActionButton("Rescan") { scanner.refresh() }
                }
            }
        }
    }

    /// A folder's name in the list: its own, `~` for your home.
    static func name(_ root: String) -> String {
        root == CodeFolders.normalized(NSHomeDirectory()) ? "~" : (root as NSString).lastPathComponent
    }

    static func status(_ scanner: CodeFolderScanner, roots: Int) -> String {
        guard scanner.scanned else { return "Looking through \(roots == 1 ? "it" : "them")…" }
        let count = plural(scanner.repos.count, "repo")
        let onGitHub = scanner.repos.values.filter { !$0.isEmpty }.count
        let line = onGitHub == scanner.repos.count ? count : "\(count), \(onGitHub) on GitHub"
        return scanner.cutShort
            ? "\(line) before stopping at \(CodeFolders.maxFolders.formatted()) folders: add the folders your code is in rather than one above them"
            : line
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose the folders your code is in"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        panel.begin { [store] response in
            guard response == .OK else { return }
            let paths = panel.urls.map(\.path)
            MainActor.assumeIsolated { store.addCodeFolders(paths) }
        }
    }
}
