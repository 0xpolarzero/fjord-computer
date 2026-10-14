import Foundation
import Testing
@testable import Fjord

@Suite struct ClaudeSSHSettingsTests {
    private func settings(_ home: TempDir) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: home.path(".claude/settings.json"))) as? [String: Any])
    }

    private func record(_ computerId: String = "computer-1", alias: String = "ssh-fjord-1") -> ClaudeSSHSettings.Computer {
        ClaudeSSHSettings.Computer(deviceId: "owner-1", computerId: computerId, computerName: "dev", ownerName: "Ari", alias: alias)
    }

    @Test func writesOneOwnedEntryAndPreservesExistingSettingsWithBackup() throws {
        let home = TempDir()
        let original = Data("{\"model\":\"opus\",\"sshConfigs\":[{\"id\":\"personal\",\"sshHost\":\"my-box\"}]}".utf8)
        try FileManager.default.createDirectory(at: home.path(".claude"), withIntermediateDirectories: true)
        try original.write(to: home.path(".claude/settings.json"))
        let writer = ClaudeSSHSettings(home: home.url)

        try writer.install(record())

        let root = try settings(home)
        #expect(root["model"] as? String == "opus")
        let entries = try #require(root["sshConfigs"] as? [[String: Any]])
        #expect(entries.count == 2)
        #expect(entries[0]["id"] as? String == "personal")
        #expect(entries[1]["id"] as? String == "fjord-owner-1-computer-1")
        #expect(entries[1]["name"] as? String == "dev · Ari")
        #expect(entries[1]["sshHost"] as? String == "ssh-fjord-1")
        #expect(entries[1]["startDirectory"] == nil)
        #expect(try Data(contentsOf: writer.backup) == original)
    }

    @Test func repeatInstallUpdatesOneMatchingRecordAndRemoveKeepsOthers() throws {
        let home = TempDir()
        let writer = ClaudeSSHSettings(home: home.url)
        try writer.install(record(alias: "ssh-old"))
        try writer.install(record(alias: "ssh-new"))
        try writer.install(record(alias: "ssh-new"))
        var entries = try #require(try settings(home)["sshConfigs"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries[0]["sshHost"] as? String == "ssh-new")

        try writer.install(record("computer-2", alias: "ssh-other"))
        try writer.remove(deviceId: "owner-1", computerId: "computer-1")
        entries = try #require(try settings(home)["sshConfigs"] as? [[String: Any]])
        #expect(entries.map { $0["id"] as? String } == ["fjord-owner-1-computer-2"])
    }

    @Test func refusesInvalidJSONAndMalformedSSHConfigShapesWithoutChangingBytes() throws {
        let home = TempDir()
        try FileManager.default.createDirectory(at: home.path(".claude"), withIntermediateDirectories: true)
        let file = home.path(".claude/settings.json")
        let malformed = Data("{broken".utf8)
        try malformed.write(to: file)
        let writer = ClaudeSSHSettings(home: home.url)
        #expect(throws: ClaudeSettingsFile.Failure.invalidJSON(file.path)) { try writer.install(record()) }
        #expect(try Data(contentsOf: file) == malformed)
        #expect(!FileManager.default.fileExists(atPath: writer.backup.path))

        for json in ["{\"sshConfigs\":{}}", "{\"sshConfigs\":[false]}"] {
            let bytes = Data(json.utf8)
            try bytes.write(to: file)
            #expect(throws: ClaudeSSHSettings.Failure.self) { try writer.install(record()) }
            #expect(try Data(contentsOf: file) == bytes)
        }
    }

    @Test func retriesAfterAnExternalEditAndWritesThroughSettingsSymlink() throws {
        let home = TempDir()
        let claude = home.path(".claude")
        let actual = home.path("dotfiles/claude-settings.json")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: actual.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"model\":\"opus\"}".utf8).write(to: actual)
        try FileManager.default.createSymbolicLink(at: claude.appendingPathComponent("settings.json"), withDestinationURL: actual)
        var injected = false
        var writer = ClaudeSSHSettings(home: home.url)
        writer.beforeReplace = {
            guard !injected else { return }
            injected = true
            try! Data("{\"model\":\"sonnet\",\"theme\":\"dark\"}".utf8).write(to: actual)
        }

        try writer.install(record())

        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: actual)) as? [String: Any])
        #expect(root["model"] as? String == "sonnet")
        #expect(root["theme"] as? String == "dark")
        #expect((root["sshConfigs"] as? [[String: Any]])?.first?["sshHost"] as? String == "ssh-fjord-1")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: claude.appendingPathComponent("settings.json").path)
            == actual.path)
    }

    @Test func retriesFollowTheCurrentSettingsSymlinkTarget() throws {
        let home = TempDir()
        let claude = home.path(".claude")
        let first = home.path("dotfiles/first.json")
        let second = home.path("dotfiles/second.json")
        let link = claude.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        let firstBytes = Data("{\"model\":\"opus\"}".utf8)
        let secondBytes = Data("{\"model\":\"sonnet\",\"theme\":\"dark\"}".utf8)
        try firstBytes.write(to: first)
        try secondBytes.write(to: second)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        var retargeted = false
        var writer = ClaudeSSHSettings(home: home.url)
        writer.beforeReplace = {
            guard !retargeted else { return }
            retargeted = true
            try! FileManager.default.removeItem(at: link)
            try! FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
        }

        try writer.install(record())

        let firstRoot = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: first)) as? [String: Any])
        let secondRoot = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: second)) as? [String: Any])
        #expect(firstRoot["sshConfigs"] == nil)
        #expect(firstRoot["model"] as? String == "opus")
        #expect(secondRoot["theme"] as? String == "dark")
        #expect((secondRoot["sshConfigs"] as? [[String: Any]])?.first?["sshHost"] as? String == "ssh-fjord-1")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == second.path)
    }
}
