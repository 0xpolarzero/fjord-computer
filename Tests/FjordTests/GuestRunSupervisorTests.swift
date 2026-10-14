import Foundation
import Darwin
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

    @Test func recorderReadinessFailureBootsOutAndStopsTheGuestRecorder() throws {
        let fixture = try GuestRunFixture()
        try fixture.writeConfig(runID: "80000000-0000-4000-8000-000000000002", recordProof: true, platform: "macos")
        let process = try fixture.launch(environment: fixture.recorderEnvironment(mode: "readiness-failure"))
        let exited = fixture.waitForExit(process)
        if !exited { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        let recorderStopped = fixture.waitUntil { !FileManager.default.fileExists(atPath: fixture.recorderRunningMarker.path) }

        #expect(exited)
        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus != 0)
        #expect(FileManager.default.fileExists(atPath: fixture.bootoutMarker.path))
        #expect(recorderStopped)
    }

    @Test func sigtermDuringRecorderStartupBootsOutAndStopsTheGuestRecorder() throws {
        let fixture = try GuestRunFixture()
        try fixture.writeConfig(runID: "80000000-0000-4000-8000-000000000003", recordProof: true, platform: "macos")
        let process = try fixture.launch(environment: fixture.recorderEnvironment(mode: "wait-for-readiness"))
        let recorderStarted = fixture.waitUntil { FileManager.default.fileExists(atPath: fixture.recorderRunningMarker.path) }
        if recorderStarted { process.terminate() }
        let exited = fixture.waitForExit(process)
        if !exited { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        let recorderStopped = fixture.waitUntil { !FileManager.default.fileExists(atPath: fixture.recorderRunningMarker.path) }

        #expect(recorderStarted)
        #expect(exited)
        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == 143)
        #expect(FileManager.default.fileExists(atPath: fixture.bootoutMarker.path))
        #expect(recorderStopped)
    }
}

private final class GuestRunFixture {
    let root: URL
    let home: URL
    let supervisor: URL
    let configPath: URL
    var proofDirectory: URL { root.appendingPathComponent("proof") }
    var recorderReadyPath: URL { proofDirectory.appendingPathComponent("recorder-ready.json") }
    var recorderRunningMarker: URL { root.appendingPathComponent("recorder-running") }
    var recorderPIDPath: URL { root.appendingPathComponent("recorder.pid") }
    var bootoutMarker: URL { root.appendingPathComponent("bootout-called") }

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

    deinit {
        if let storedPID = try? String(contentsOf: recorderPIDPath, encoding: .utf8),
           let pid = Int32(storedPID.trimmingCharacters(in: .whitespacesAndNewlines)) {
            _ = kill(pid, SIGKILL)
        }
        try? FileManager.default.removeItem(at: root)
    }

    func writeConfig(runID: String, recordProof: Bool, platform: String = "linux") throws {
        let object: [String: Any] = [
            "runID": runID,
            "home": home.path,
            "cwd": root.appendingPathComponent("workspace").path,
            "videoPath": root.appendingPathComponent("proof/run.mp4").path,
            "manifestPath": root.appendingPathComponent("proof/manifest.json").path,
            "recorderArchivePath": root.appendingPathComponent("recorder.zip").path,
            "recordProof": recordProof,
            "platform": platform,
            "claude": root.appendingPathComponent("fake-claude").path,
            "prompt": "Fix the task",
            "permissionMode": "default",
            "allowedTools": ["Read"],
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: configPath)
    }

    func recorderEnvironment(mode: String) throws -> [String: String] {
        let preload = root.appendingPathComponent("preload.cjs")
        let ditto = root.appendingPathComponent("ditto-stub")
        let launchctl = root.appendingPathComponent("launchctl-stub.js")
        let recorder = root.appendingPathComponent("guest-recorder.js")
        let launchctlLog = root.appendingPathComponent("launchctl.log")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: ditto)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ditto.path)
        try Data("""
        const fs = require("node:fs");
        const cp = require("node:child_process");
        const originalSpawn = cp.spawn;
        const substitutions = new Map([["/usr/bin/ditto", process.env.FJORD_TEST_DITTO], ["/bin/launchctl", process.env.FJORD_TEST_LAUNCHCTL]]);
        cp.spawn = function(command, args, options) { return originalSpawn.call(this, substitutions.get(command) || command, args, options); };
        require("node:module").syncBuiltinESMExports();
        """.utf8).write(to: preload)
        try Data("""
        const fs = require("node:fs");
        fs.writeFileSync(process.env.FJORD_TEST_RECORDER_RUNNING, String(process.pid));
        process.on("SIGTERM", () => { fs.rmSync(process.env.FJORD_TEST_RECORDER_RUNNING, { force: true }); process.exit(0); });
        setInterval(() => {}, 1000);
        """.utf8).write(to: recorder)
        try Data("""
        #!/usr/bin/env node
        const fs = require("node:fs");
        const cp = require("node:child_process");
        const action = process.argv[2];
        fs.appendFileSync(process.env.FJORD_TEST_LAUNCHCTL_LOG, `${process.argv.slice(2).join(" ")}\\n`);
        if (action === "bootstrap") {
          const child = cp.spawn(process.execPath, [process.env.FJORD_TEST_RECORDER], { detached: true, stdio: "ignore" });
          child.unref();
          fs.writeFileSync(process.env.FJORD_TEST_RECORDER_PID, String(child.pid));
        } else if (action === "kickstart" && process.env.FJORD_TEST_RECORDER_MODE === "readiness-failure") {
          fs.writeFileSync(process.env.FJORD_TEST_RECORDER_READY, JSON.stringify({ state: "failed", error: "fixture readiness failure" }));
        } else if (action === "bootout") {
          fs.writeFileSync(process.env.FJORD_TEST_BOOTOUT, "called");
          try { process.kill(Number(fs.readFileSync(process.env.FJORD_TEST_RECORDER_PID, "utf8")), "SIGTERM"); } catch {}
        }
        """.utf8).write(to: launchctl)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launchctl.path)

        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["CLAUDE_CODE_OAUTH_TOKEN"] = "$MSB_TEST_TOKEN"
        environment["FJORD_TEST_DITTO"] = ditto.path
        environment["FJORD_TEST_LAUNCHCTL"] = launchctl.path
        environment["FJORD_TEST_LAUNCHCTL_LOG"] = launchctlLog.path
        environment["FJORD_TEST_RECORDER"] = recorder.path
        environment["FJORD_TEST_RECORDER_MODE"] = mode
        environment["FJORD_TEST_RECORDER_READY"] = recorderReadyPath.path
        environment["FJORD_TEST_RECORDER_RUNNING"] = recorderRunningMarker.path
        environment["FJORD_TEST_RECORDER_PID"] = recorderPIDPath.path
        environment["FJORD_TEST_BOOTOUT"] = bootoutMarker.path
        let requirePreload = "--require=\(preload.path)"
        environment["NODE_OPTIONS"] = [environment["NODE_OPTIONS"], requirePreload].compactMap { $0 }.joined(separator: " ")
        return environment
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

    func waitForExit(_ process: Process, timeout: TimeInterval = 5) -> Bool {
        waitUntil(timeout: timeout) { !process.isRunning }
    }

    func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }
}
