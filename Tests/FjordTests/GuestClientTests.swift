import CryptoKit
import Foundation
import Testing
@testable import Fjord

@Suite struct GuestClientTests {
    private let computer = GuestReference(deviceId: "owner-1", computerId: "computer-1")
    private var account: GuestAccount {
        GuestAccount(home: "/home/guest", uid: 1001, operatingSystem: .linux, architecture: "aarch64",
                     nodeExecutable: "/usr/bin/node", claudeExecutable: "/home/guest/.local/bin/claude")
    }

    private func client() -> MockGuestClient { MockGuestClient(accounts: [computer: account]) }

    @Test func writeIsAtomicAtRequestedModeAndReadsRangesWithMetadata() async throws {
        let guest = client()
        let request = GuestFileWriteRequest(computer: computer, path: "/home/guest/.local/share/fjord/forms/a.json",
                                            data: Data("abcdef".utf8), mode: 0o600, createParents: true)
        let written = try await guest.filesWrite(request)
        let read = try await guest.filesRead(computer: computer, path: request.path, offset: 2, length: 3)

        #expect(read.data == Data("cde".utf8))
        #expect(read.size == 6)
        #expect(read.mode == 0o600)
        #expect(read.inode == written.inode)
        #expect(await guest.writeRecords().count == 1)
    }

    @Test func createOnlyAndSHA256ReplacementHaveDifferentConflictResults() async throws {
        let guest = client()
        let path = "/home/guest/.claude/settings.json"
        try await guest.filesWrite(.init(computer: computer, path: path, data: Data("{}".utf8), mode: 0o600,
                                         replace: .ifSHA256(nil)))
        do {
            _ = try await guest.filesWrite(.init(computer: computer, path: path, data: Data("answer".utf8), mode: 0o600,
                                                replace: .never))
            Issue.record("create-only write replaced an existing file")
        } catch { #expect(error as? GuestClientFailure == .exists(path)) }

        do {
            _ = try await guest.filesWrite(.init(computer: computer, path: path, data: Data("changed".utf8), mode: 0o600,
                                                replace: .ifSHA256("bad-hash")))
            Issue.record("conditional write ignored a stale digest")
        } catch { #expect(error as? GuestClientFailure == .changed(path)) }

        let original = try await guest.filesRead(computer: computer, path: path, offset: nil, length: nil)
        let digest = SHA256.hash(data: original.data).map { String(format: "%02x", $0) }.joined()
        try await guest.filesWrite(.init(computer: computer, path: path, data: Data("updated".utf8), mode: 0o600,
                                         replace: .ifSHA256(digest)))
        #expect(try await guest.filesRead(computer: computer, path: path, offset: nil, length: nil).data == Data("updated".utf8))
    }

    @Test func watchEmitsHintsAndListReturnsOnlyDirectChildren() async throws {
        let guest = client()
        try await guest.filesWrite(.init(computer: computer, path: "/home/guest/forms/a.json", data: Data("a".utf8), mode: 0o600))
        let watch = try await guest.filesWatch(computer: computer, paths: ["/home/guest/forms"])
        var iterator = watch.events.makeAsyncIterator()
        try await guest.filesWrite(.init(computer: computer, path: "/home/guest/forms/nested/b.json", data: Data("b".utf8), mode: 0o600))
        let event = await iterator.next()
        let entries = try await guest.filesList(computer: computer, path: "/home/guest/forms")

        #expect(event?.subscriptionId == watch.subscriptionId)
        #expect(event?.path == "/home/guest/forms/nested/b.json")
        #expect(entries.map(\.name) == ["a.json", "nested"])
        #expect(entries.last?.type == .directory)
    }

    @Test func guestRootsAreNotHostFilesAndPathsMustBeAbsolute() async throws {
        let guest = client()
        let path = "/home/guest/.local/share/fjord/router/test.txt"
        try await guest.filesWrite(.init(computer: computer, path: path, data: Data("guest".utf8), mode: 0o600))

        #expect(FileManager.default.fileExists(atPath: path) == false)
        #expect(await guest.filesSnapshot(for: computer)[path] == Data("guest".utf8))
        #expect(throws: GuestFolderPath.Failure.absolutePathRequired) {
            try GuestFolderPath.validate("relative")
        }
    }
}
