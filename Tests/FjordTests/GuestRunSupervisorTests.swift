import Foundation
import Testing

@Suite(.serialized) struct GuestRunSupervisorTests {
    @Test func standardUUIDConfigReachesClaude() throws {
        let fixture = try GuestRunFixture()
        try fixture.writeConfig(runID: "80000000-0000-4000-8000-000000000001", recordProof: false)
        let argsPath = fixture.root.appendingPathComponent("claude-args.txt")
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = fixture.home.path
        environment["CLAUDE_CODE_OAUTH_TOKEN"] = "$MSB_TEST_TOKEN"
        environment["CLAUDE_ARGS_OUT"] = argsPath.path

        let process = try fixture.launch(environment: environment)
        process.waitUntilExit()

        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == 0)
        let args = try String(contentsOf: argsPath, encoding: .utf8)
        #expect(args.contains("Fix the task"))
    }
}

private final class GuestRunFixture {
    let root: URL
    let home: URL
    let supervisor: URL
    let configPath: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fjord-guest-run-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        supervisor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/GuestRuns/run.mjs")
        configPath = root.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("workspace"), withIntermediateDirectories: true)
        let claude = root.appendingPathComponent("fake-claude")
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$CLAUDE_ARGS_OUT\"\nexit 0\n".utf8).write(to: claude)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: claude.path)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func writeConfig(runID: String, recordProof: Bool, platform: String = "linux") throws {
        let object: [String: Any] = [
            "runID": runID,
            "home": home.path,
            "cwd": root.appendingPathComponent("workspace").path,
            "videoPath": root.appendingPathComponent("proof/run.mp4").path,
            "manifestPath": root.appendingPathComponent("proof/manifest.json").path,
            "recordProof": recordProof,
            "platform": platform,
            "claude": root.appendingPathComponent("fake-claude").path,
            "prompt": "Fix the task",
            "permissionMode": "default",
            "allowedTools": ["Read"],
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: configPath)
    }

    func launch(environment: [String: String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", supervisor.path, configPath.path]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}
