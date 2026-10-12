import Foundation
import Testing
@testable import FjordComputer

/// A folder tree of a test's own, in the temporary folder, gone when the test ends.
private final class Tree {
    let root: String
    private let fm = FileManager.default

    init() {
        root = fm.temporaryDirectory.appendingPathComponent("fjord-code-\(UUID().uuidString)", isDirectory: true).path
        try? fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    deinit { try? fm.removeItem(atPath: root) }

    func path(_ relative: String) -> String { (root as NSString).appendingPathComponent(relative) }

    func folder(_ relative: String) {
        try? fm.createDirectory(atPath: path(relative), withIntermediateDirectories: true)
    }

    func file(_ relative: String, _ text: String) {
        folder((relative as NSString).deletingLastPathComponent)
        fm.createFile(atPath: path(relative), contents: Data(text.utf8))
    }

    /// A repo at `relative` whose config has these remotes (name, url).
    func repo(_ relative: String, remotes: [(String, String)] = []) {
        let config = remotes.map { "[remote \"\($0.0)\"]\n\turl = \($0.1)\n\tfetch = +refs/heads/*:refs/remotes/\($0.0)/*\n" }
        file("\(relative)/.git/config", "[core]\n\tbare = false\n" + config.joined())
    }
}

@Suite struct CodeFolderScanning {
    @Test func reposAreFoundDownToTheDepthAndNotInsideAnother() {
        let tree = Tree()
        tree.repo("a", remotes: [("origin", "git@github.com:Me/A.git")])
        // Inside a repo: not looked into.
        tree.repo("a/vendored/inner", remotes: [("origin", "https://github.com/o/inner")])
        tree.repo("b/c/d/e", remotes: [("origin", "https://github.com/o/e")])
        tree.repo("b/c/d/e2/f", remotes: [("origin", "https://github.com/o/f")])
        tree.repo("local")
        tree.repo("elsewhere", remotes: [("origin", "https://gitlab.com/o/elsewhere")])
        let found = CodeFolders.scan(roots: [tree.root], home: "/nowhere")
        #expect(found.repos == [tree.path("a"): ["me/a"], tree.path("b/c/d/e"): ["o/e"], tree.path("local"): [],
                                tree.path("elsewhere"): []])
        #expect(!found.cutShort)
        // A root that is a repo is that repo; the same root twice, or written with `/` or `~`, is looked through once.
        #expect(CodeFolders.scan(roots: [tree.path("a") + "/", tree.path("a")], home: "/nowhere").repos == [tree.path("a"): ["me/a"]])
        #expect(CodeFolders.normalized("~/code/") == NSHomeDirectory() + "/code")
    }

    @Test func buildHiddenLinkedAndPackagedFoldersArePassedOver() throws {
        let tree = Tree()
        for skipped in ["node_modules/x", ".hidden/y", "build/z", "DerivedData/w", "Pods/v", "Bundle.app/u"] {
            tree.repo(skipped, remotes: [("origin", "https://github.com/o/skipped")])
        }
        let other = Tree()
        other.repo("linked", remotes: [("origin", "https://github.com/o/linked")])
        try FileManager.default.createSymbolicLink(atPath: tree.path("link"), withDestinationPath: other.path("linked"))
        try FileManager.default.createSymbolicLink(atPath: tree.path("linkabove"), withDestinationPath: other.root)
        tree.repo("kept", remotes: [("origin", "https://github.com/o/kept")])
        #expect(CodeFolders.scan(roots: [tree.root], home: "/nowhere").repos == [tree.path("kept"): ["o/kept"]])
    }

    @Test func theFoldersTheSystemGuardsAreOnlyLookedThroughWhenAdded() {
        let tree = Tree()
        tree.repo("Documents/notes", remotes: [("origin", "https://github.com/o/notes")])
        tree.repo("Library/thing", remotes: [("origin", "https://github.com/o/thing")])
        tree.repo("code/app", remotes: [("origin", "https://github.com/o/app")])
        // The tree stands for your home: added whole, its Documents and Library are passed over.
        #expect(CodeFolders.scan(roots: [tree.root], home: tree.root).repos == [tree.path("code/app"): ["o/app"]])
        #expect(CodeFolders.scan(roots: [tree.path("Documents")], home: tree.root).repos == [tree.path("Documents/notes"): ["o/notes"]])
    }

    @Test func aScanStopsAtItsFolderBudgetShallowFirst() {
        let tree = Tree()
        tree.repo("near", remotes: [("origin", "https://github.com/o/near")])
        for i in 0..<20 { tree.folder("wide/\(i)") }
        tree.repo("wide/19/deep", remotes: [("origin", "https://github.com/o/deep")])
        let cut = CodeFolders.scan(roots: [tree.root], maxFolders: 10, home: "/nowhere")
        #expect(cut.cutShort)
        #expect(cut.repos == [tree.path("near"): ["o/near"]])
        let whole = CodeFolders.scan(roots: [tree.root], home: "/nowhere")
        #expect(!whole.cutShort && whole.repos.count == 2)
    }

    @Test func aWorktreeHasItsRepositorysRemotes() {
        let tree = Tree()
        tree.repo("app", remotes: [("origin", "git@github.com:o/app.git")])
        // `git worktree add`: the worktree's `.git` is a file pointing at the repo's git dir, whose `commondir` leads back.
        tree.file("app/.git/worktrees/feature/commondir", "../..\n")
        tree.file("feature/.git", "gitdir: \(tree.path("app/.git/worktrees/feature"))\n")
        // Relative, as `git worktree add --relative-paths` writes it.
        tree.file("app/.git/worktrees/relative/commondir", "../..\n")
        tree.file("relative/.git", "gitdir: ../app/.git/worktrees/relative\n")
        // A submodule's git dir has its own config, and no commondir.
        tree.file("app/.git/modules/lib/config", "[remote \"origin\"]\n\turl = https://github.com/o/lib\n")
        tree.file("lib/.git", "gitdir: ../app/.git/modules/lib\n")
        let found = CodeFolders.scan(roots: [tree.root], home: "/nowhere")
        #expect(found.repos[tree.path("feature")] == ["o/app"])
        #expect(found.repos[tree.path("relative")] == ["o/app"])
        #expect(found.repos[tree.path("lib")] == ["o/lib"])
        #expect(LocalClones.remotes(of: tree.path("feature")) == ["o/app"])
    }

    @Test func aConfigsRemotesAreReadOriginFirst() {
        let config = """
        [core]
        \turl = https://github.com/not/aremote
        [remote "upstream"]
        \turl = https://github.com/Owner/Repo.git
        [submodule "lib"]
        \turl = https://github.com/o/lib
        [remote "origin"]
        \tURL = "git@github.com:me/repo.git"
        \tpushurl = https://github.com/me/push
        [remote "mirror"]
        \turl = https://github.com/me/repo
        [remote "gitlab"]
        \turl = https://gitlab.com/me/repo
        # url = https://github.com/commented/out
        """
        #expect(CodeFolders.remotes(config: config) == ["me/repo", "owner/repo"])
    }
}

@MainActor
@Suite(.serialized) struct CodeFolderStore {
    private func store(scan: @escaping @Sendable ([String]) -> CodeFolders.Found) -> Store {
        let s = Store()
        s.persists = false
        s.codeFolders.scan = scan
        return s
    }

    @Test func clonesAreFoundAmongSessionsAndScannedReposAlike() async {
        let tree = Tree()
        // A session's folder no scan reached: read when asked.
        tree.repo("session-only", remotes: [("origin", "https://github.com/o/app")])
        let session = tree.path("session-only")
        let s = store { _ in .init(repos: ["/code/app": ["o/app", "up/app"], "/code/other": ["o/other"], "/code/local": []]) }
        s.claudeSessions = ["a": ClaudeSession(id: "a", title: "a", folder: session, lastActivity: Date()),
                            "b": ClaudeSession(id: "b", title: "b", folder: "/code/app", lastActivity: Date())]
        #expect(s.localClones(of: "o/app") == [session])
        s.addCodeFolders(["/code", "/code/"])
        #expect(s.codeFolderRoots == ["/code"])
        await s.codeFolders.settled()
        #expect(s.localClones(of: "O/App") == ["/code/app", session])
        #expect(s.localClones(of: "up/app") == ["/code/app"])
        #expect(s.localClones(of: "o/none").isEmpty)
        // Every project, once each, sorted by name; the Router's own destinations stay the sessions' folders.
        #expect(s.projectFolders == ["/code/app", "/code/local", "/code/other", session])
        #expect(Set(s.knownFolders) == [session, "/code/app"])
        #expect(s.codeRepos.count == 3)
    }

    @Test func atOffersTheReposFoundInCodeFoldersAsProjects() async {
        let s = store { _ in .init(repos: ["/code/app": ["o/app"], "/code/tool": []]) }
        s.claudeSessions = ["a": ClaudeSession(id: "a", title: "a", folder: "/x/lookout", lastActivity: Date())]
        s.addCodeFolders(["/code"])
        await s.codeFolders.settled()
        let projects = RouterMentions.candidates(s).compactMap(\.folder)
        #expect(projects == s.projectFolders && Set(projects) == ["/code/app", "/code/tool", "/x/lookout"])
        // Typed, picked: a project's pill like any other.
        let model = RouterModel()
        model.draft = "in @too"
        let found = model.suggestions(s)
        #expect(found.first?.folder == "/code/tool")
        model.pickMention(found[0])
        #expect(model.projects == ["/code/tool"])
    }

    @Test func scannedFoldersAreNamedAndTellSameNamedProjectsApart() async {
        let s = store { _ in .init(repos: ["/y/app": ["o/app"], "/y/tool": []]) }
        s.claudeSessions = ["a": ClaudeSession(id: "a", title: "a", folder: "/x/app", lastActivity: Date())]
        #expect(s.folderName("/x/app") == "app")
        s.addCodeFolders(["/y"])
        await s.codeFolders.settled()
        #expect(s.folderNames["/x/app"] == "x/app" && s.folderNames["/y/app"] == "y/app" && s.folderNames["/y/tool"] == "tool")
        // Without the code folder, the session's project is named by itself again.
        s.removeCodeFolder("/y")
        #expect(s.settings.codeFolders == nil)
        await s.codeFolders.settled()
        #expect(s.codeRepos.isEmpty)
        #expect(s.folderName("/x/app") == "app")
    }

    @Test func settingsListTheFoldersAndHowManyReposTheyHold() async throws {
        let s = store { _ in .init(repos: ["/code/app": ["o/app"], "/code/local": []]) }
        s.settings.triage = true
        s.addCodeFolders(["/code"])
        await s.codeFolders.settled()
        #expect(CodeFoldersSettings.status(s.codeFolders, roots: 1) == "2 repos, 1 on GitHub")
        let tree = try await AccessibilityTree.render(SettingsView(store: s, hub: HubState()).frame(width: 440, height: 2400),
                                                      size: CGSize(width: 440, height: 2400))
        #expect(tree.all.contains { $0.role == "AXButton" && $0.label == "Add a code folder" })
        #expect(tree.all.contains { $0.role == "AXButton" && $0.label == "Remove code" })
        #expect(tree.all.contains { $0.role == "AXButton" && $0.label == "Rescan" })
    }

    @Test func requestsDuringAScanFoldIntoOneMore() async {
        final class Count: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            var value: Int { lock.withLock { n } }
            func add() { lock.withLock { n += 1 } }
        }
        let count = Count()
        let s = store { roots in
            count.add()
            Thread.sleep(forTimeInterval: 0.2)
            return .init(repos: Dictionary(uniqueKeysWithValues: roots.map { ($0 + "/repo", []) }))
        }
        s.addCodeFolders(["/a"])
        while count.value == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        // Asked again while the first scan runs, and the folders changed meanwhile: one more scan, of the folders as they are.
        s.codeFolders.refresh()
        s.codeFolders.refresh()
        s.addCodeFolders(["/b"])
        await s.codeFolders.settled()
        #expect(count.value == 2)
        #expect(Set(s.codeRepos.keys) == ["/a/repo", "/b/repo"])
        #expect(s.codeFolders.scanned)
        // No code folders: nothing is looked through, and nothing is found.
        s.removeCodeFolder("/a")
        s.removeCodeFolder("/b")
        await s.codeFolders.settled()
        #expect(count.value == 2 && s.codeRepos.isEmpty)
    }
}
