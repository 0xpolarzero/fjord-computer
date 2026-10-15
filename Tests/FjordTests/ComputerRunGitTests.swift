import Foundation
import Testing
@testable import Fjord

@Suite(.serialized, .ownGuestRuntime) struct ComputerRunGitTests {
    @Test func freshCloneCanCreateRunBranchFromHeadWithoutFetchHead() throws {
        let fixture = try LocalGitFixture()
        let clone = try fixture.cloneSeed()
        let fetchHead = clone.appendingPathComponent(".git/FETCH_HEAD")
        try? FileManager.default.removeItem(at: fetchHead)
        #expect(!FileManager.default.fileExists(atPath: fetchHead.path))

        let arguments = ComputerRunGit.createRunBranchArguments(path: clone.path, branch: "fjord/triage/clone-test", from: .freshClone)
        let result = try fixture.git(arguments, allowFailure: true)

        #expect(result.status == 0)
        let branchHead = try fixture.git(["-C", clone.path, "rev-parse", "fjord/triage/clone-test"])
        #expect(branchHead.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == fixture.seedCommit)
    }

    @Test func fetchedCloneCanCreateRunBranchFromFetchHead() throws {
        let fixture = try LocalGitFixture()
        let clone = try fixture.cloneSeed()
        try fixture.addSeedCommit("second")
        _ = try fixture.git(["-C", clone.path, "fetch", "--depth=1", "origin", "HEAD"])

        let arguments = ComputerRunGit.createRunBranchArguments(path: clone.path, branch: "fjord/triage/fetch-test", from: .afterFetch)
        let result = try fixture.git(arguments)

        #expect(result.status == 0)
        let branchHead = try fixture.git(["-C", clone.path, "rev-parse", "fjord/triage/fetch-test"])
        #expect(branchHead.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == fixture.latestSeedCommit)
    }
}

private final class LocalGitFixture {
    let root: URL
    let origin: URL
    let seed: URL
    let clone: URL
    private(set) var seedCommit = ""
    private(set) var latestSeedCommit = ""

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fjord-run-git-\(UUID().uuidString)")
        origin = root.appendingPathComponent("origin.git")
        seed = root.appendingPathComponent("seed")
        clone = root.appendingPathComponent("clone")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try git(["init", "--bare", "--initial-branch=main", origin.path])
        _ = try git(["init", "--initial-branch=main", seed.path])
        _ = try git(["-C", seed.path, "config", "user.name", "Fjord Git Tests"])
        _ = try git(["-C", seed.path, "config", "user.email", "fjord-git-tests@example.invalid"])
        try Data("seed\n".utf8).write(to: seed.appendingPathComponent("seed.txt"))
        _ = try git(["-C", seed.path, "add", "seed.txt"])
        _ = try git(["-C", seed.path, "commit", "-m", "seed"])
        _ = try git(["-C", seed.path, "remote", "add", "origin", origin.path])
        _ = try git(["-C", seed.path, "push", "origin", "HEAD:refs/heads/main"])
        seedCommit = try git(["-C", seed.path, "rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        latestSeedCommit = seedCommit
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func cloneSeed() throws -> URL {
        _ = try git(["clone", "--depth=1", origin.path, clone.path])
        return clone
    }

    func addSeedCommit(_ contents: String) throws {
        try Data("\(contents)\n".utf8).write(to: seed.appendingPathComponent("seed.txt"))
        _ = try git(["-C", seed.path, "add", "seed.txt"])
        _ = try git(["-C", seed.path, "commit", "-m", contents])
        _ = try git(["-C", seed.path, "push", "origin", "HEAD:refs/heads/main"])
        latestSeedCommit = try git(["-C", seed.path, "rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func git(_ arguments: [String], allowFailure: Bool = false) throws -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        // Nothing of the machine's own git setup (default branch, identity, hooks, templates) may shape the fixture.
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let result = GitResult(status: process.terminationStatus, stdout: output, stderr: error)
        guard allowFailure || result.status == 0 else {
            throw GitFailure(arguments: arguments, status: result.status, stderr: result.stderr)
        }
        return result
    }
}

private struct GitResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private struct GitFailure: Error, CustomStringConvertible {
    let arguments: [String]
    let status: Int32
    let stderr: String

    var description: String { "git \(arguments.joined(separator: " ")) exited \(status): \(stderr)" }
}
