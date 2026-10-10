import Foundation
import Testing
@testable import Lookout

/// Preparing a message with Haiku (a fake Claude Code stands in), and the pieces of starting a session.
@Suite struct RouterPrepare {
    // MARK: Haiku's answer

    @Test func anAnswerIsHeldToTheRules() throws {
        let original = "tell lookout to bump the version"
        let rephrased = try Rephrase.parse(#"{"rephrased": true, "text": "Bump the version."}"#, original: original)
        #expect(rephrased == Prepared(text: "Bump the version.", original: original, rephrased: true))
        // Fenced, or with words around it: the JSON is found.
        let fenced = try Rephrase.parse("```json\n{\"rephrased\":true,\"text\":\"Bump the version.\"}\n```", original: original)
        #expect(fenced.text == "Bump the version." && fenced.rephrased)
        // Not rephrased: the original, byte for byte, whatever text came back.
        let kept = try Rephrase.parse(#"{"rephrased": false, "text": "Tell lookout to bump the version."}"#, original: original)
        #expect(kept == Prepared(text: original, original: original, rephrased: false))
        // "Rephrased" to the same words: unchanged. To nothing: refused, not replaced by the original.
        #expect(try Rephrase.parse(#"{"rephrased": true, "text": "tell lookout to bump the version"}"#, original: original).rephrased == false)
        #expect(throws: Rephrase.NothingLeft.self) { try Rephrase.parse(#"{"rephrased": true, "text": "  \n"}"#, original: original) }
        // Kept exactly as given: indentation and trailing newlines in code matter.
        let code = try Rephrase.parse(#"{"rephrased": true, "text": "Run:\n    swift test\n"}"#, original: original)
        #expect(code.text == "Run:\n    swift test\n")
        #expect(throws: RouterTools.Failure.self) { try Rephrase.parse("Sure! Here it is: Bump the version.", original: original) }
        #expect(throws: RouterTools.Failure.self) { try Rephrase.parse(#"{"text": "x"}"#, original: original) }
    }

    /// A stand-in for Claude Code: keeps its arguments and stdin, then prints `output`.
    private func fake(_ dir: TempDir, output: String, sleep: Double = 0) -> String {
        let path = dir.path("claude").path
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(dir.path("args").path)'
        cat > '\(dir.path("stdin").path)'
        sleep \(sleep)
        cat <<'EOF'
        \(output)
        EOF
        """
        FileManager.default.createFile(atPath: path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
        return path
    }

    @Test func aRunGoesThroughTheBinaryAloneWithNoToolsAndBack() async throws {
        let dir = TempDir()
        let answer = #"{"type":"result","subtype":"success","is_error":false,"result":"{\"rephrased\":true,\"text\":\"Bump the version.\"}"}"#
        let binary = fake(dir, output: answer)
        let out = try await Rephrase.run(binary: binary, cwd: dir.url, message: "tell lookout to bump the version",
                                         title: "Release", project: "lookout", timeout: 120)
        #expect(out == Prepared(text: "Bump the version.", original: "tell lookout to bump the version", rephrased: true))
        let stdin = try String(contentsOf: dir.path("stdin"), encoding: .utf8)
        // Haiku is told the target as well as the message.
        #expect(stdin.contains("Release") && stdin.hasSuffix("tell lookout to bump the version"))
        // Alone: no tools, no settings, no MCP servers of the user's, nothing saved.
        let args = try String(contentsOf: dir.path("args"), encoding: .utf8).components(separatedBy: "\n")
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).map { args[$0 + 1] } }
        #expect(value("--tools") == "" && value("--setting-sources") == "")
        #expect(args.contains("--strict-mcp-config") && args.contains("--no-session-persistence"))
    }

    @Test func aFailedOrSlowRunIsAnError() async throws {
        let dir = TempDir()
        let failed = fake(dir, output: #"{"type":"result","is_error":true,"errors":["Model not available"]}"#)
        await #expect(throws: RouterTools.Failure.self) {
            try await Rephrase.run(binary: failed, cwd: dir.url, message: "hi", title: "t", project: "p")
        }
        let slow = TempDir()
        let binary = fake(slow, output: "{}", sleep: 5)
        let start = Date()
        await #expect(throws: OneShot.TimedOut.self) {
            try await Rephrase.run(binary: binary, cwd: slow.url, message: "hi", title: "t", project: "p", timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(start) < 60)
    }

    // MARK: Starting a session

    @Test func theBootstrapRenamesAndMakesNoModelCall() throws {
        // No permission mode: the app gives the imported session the one in the user's settings.
        let args = SessionStart.bootstrapArguments(uuid: "u-1", title: "Bump the version")
        #expect(args == ["-p", "/rename Bump the version", "--session-id", "u-1", "--output-format", "json", "--setting-sources", ""])
        #expect(SessionStart.importURL(uuid: "abc")?.absoluteString == "claude://resume?session=abc")
        #expect(SessionStart.cleanTitle("  Bump\nthe   version  ") == "Bump the version")
    }

    @Test func theNewSessionsProcessIsWaitedFor() async throws {
        let dir = TempDir()
        let peers = dir.path("sessions")
        try FileManager.default.createDirectory(at: peers, withIntermediateDirectories: true)
        Task.detached {
            try? await Task.sleep(nanoseconds: 300_000_000)
            let data = try? JSONSerialization.data(withJSONObject: ["pid": Int(getpid()), "hostSessionId": "local_u-9", "name": "Bump the version"])
            try? data?.write(to: peers.appendingPathComponent("\(getpid()).json"))
        }
        #expect(try await SessionStart.waitForPeer(uuid: "u-9", dir: peers, timeout: 120) == "Bump the version")
        await #expect(throws: RouterTools.Failure.self) { try await SessionStart.waitForPeer(uuid: "other", dir: peers, timeout: 0.5) }
    }

    // MARK: One run, bounded

    private func script(_ dir: TempDir, _ name: String, _ body: String) -> String {
        let path = dir.path(name).path
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n\(body)\n".utf8), attributes: [.posixPermissions: 0o755])
        return path
    }

    private func alive(_ pid: Int32) -> Bool { pid > 0 && kill(pid, 0) == 0 }

    @Test func aProgramThatNeverReadsItsInputDoesntHoldTheRun() async throws {
        let dir = TempDir()
        // 4 MB of input it never reads; it answers and exits.
        let path = script(dir, "deaf", "echo done")
        let out = try await OneShot.run(path, [], cwd: dir.url, input: Data(count: 4 << 20), timeout: 120)
        #expect(String(decoding: out.stdout, as: UTF8.self) == "done\n" && out.status == 0)
        // Never reading and never exiting: the deadline ends it, covering the blocked write too.
        let stuck = script(dir, "stuck", "exec sleep 30")
        let handle = OneShot.Handle()
        let start = Date()
        await #expect(throws: OneShot.TimedOut.self) {
            try await OneShot.run(stuck, [], cwd: dir.url, input: Data(count: 4 << 20), timeout: 1, handle: handle)
        }
        #expect(Date().timeIntervalSince(start) < 60)
        #expect(handle.pid > 0 && !handle.isActive && !alive(handle.pid))
    }

    @Test func aChildLeftHoldingTheOutputDoesntHoldTheRun() async throws {
        let dir = TempDir()
        // It exits at once, but leaves a child that keeps its stdout and stderr open for 30 s.
        let path = script(dir, "leaver", "sleep 30 & echo $! > '\(dir.path("child.pid").path)'; echo answer")
        let start = Date()
        let out = try await OneShot.run(path, [], cwd: dir.url, timeout: 120)
        #expect(String(decoding: out.stdout, as: UTF8.self) == "answer\n")
        // Not held by the child (it holds the pipes for 30 s).
        #expect(Date().timeIntervalSince(start) < 25)
        if let child = Int32((try? String(contentsOf: dir.path("child.pid"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") {
            kill(child, SIGKILL)
        }
    }

    @Test func cancellingEndsTheProgramEvenIfItIgnoresSIGTERM() async throws {
        let dir = TempDir()
        let path = script(dir, "stubborn", #"exec /usr/bin/perl -e '$SIG{TERM} = "IGNORE"; sleep 1 while 1'"#)
        let handle = OneShot.Handle()
        let running = Task { try await OneShot.run(path, [], cwd: dir.url, timeout: 60, handle: handle) }
        while !handle.isRunning { try await Task.sleep(nanoseconds: 10_000_000) }
        try await Task.sleep(nanoseconds: 300_000_000)
        let pid = handle.pid
        let start = Date()
        running.cancel()
        await #expect(throws: CancellationError.self) { try await running.value }
        #expect(!alive(pid) && !handle.isRunning && Date().timeIntervalSince(start) < 25)
        // Ended before it started: never run.
        let early = OneShot.Handle()
        early.cancel()
        await #expect(throws: CancellationError.self) { try await OneShot.run(path, [], cwd: dir.url, timeout: 60, handle: early) }
        #expect(early.pid == 0)
    }

    // MARK: Reading the pipes

    @Test func aReadUnderWayIsWaitedForBeforeThePipeCloses() throws {
        let pipe = Pipe()
        let reader = OneShot.PipeReader(pipe.fileHandleForReading)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let first = FormWriter.Flag()
        // The reader's first read is held in flight.
        reader.aroundRead = {
            guard !first.isSet else { return }
            first.set()
            entered.signal()
            release.wait()
        }
        reader.start()
        try pipe.fileHandleForWriting.write(contentsOf: Data("hello".utf8))
        #expect(entered.wait(timeout: .now() + 120) == .success)
        reader.stop()
        let done = FormWriter.Flag()
        DispatchQueue.global().async { reader.waitDone(); done.set() }
        // While its read is under way, stopping doesn't count as done: the pipe can't be closed under it.
        Thread.sleep(forTimeInterval: 0.2)
        #expect(!done.isSet)
        release.signal()
        let until = Date().addingTimeInterval(120)
        while !done.isSet, Date() < until { Thread.sleep(forTimeInterval: 0.01) }
        #expect(done.isSet)
        // Now it's safe to close; what was read is kept.
        try pipe.fileHandleForReading.close()
        #expect(reader.data == Data("hello".utf8))
    }

    @Test func aDescendantFeedingThePipeForeverDoesntHoldTheRun() async throws {
        let dir = TempDir()
        // It leaves a child that writes to the shared output without end, then exits.
        let path = script(dir, "flood", "(while :; do echo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx; done) & echo $! > '\(dir.path("flood.pid").path)'; echo answer")
        defer {
            if let pid = Int32(((try? String(contentsOf: dir.path("flood.pid"), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) {
                kill(pid, SIGKILL)
            }
        }
        let start = Date()
        let out = try await OneShot.run(path, [], cwd: dir.url, timeout: 120)
        // Returned past the grace and a bounded last drain, not held by the child; and the output is capped.
        #expect(Date().timeIntervalSince(start) < 60)
        #expect(out.stdout.range(of: Data("answer".utf8)) != nil)
        #expect(out.stdout.count <= OneShot.PipeReader.maxBytes)
    }

    @Test func aDescendantHoldingStdinDoesntKeepTheInputAlive() async throws {
        let dir = TempDir()
        // It leaves a child holding its stdin (checked with lsof: fd 0 is the pipe) that never reads, and exits at once; the input is far more than a pipe holds.
        let path = script(dir, "holder", "sleep 600 <&0 & echo $! > '\(dir.path("holder.pid").path)'; echo done")
        defer {
            if let pid = Int32(((try? String(contentsOf: dir.path("holder.pid"), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) {
                kill(pid, SIGKILL)
            }
        }
        let handle = OneShot.Handle()
        let start = Date()
        let out = try await OneShot.run(path, [], cwd: dir.url, input: Data(count: 8 << 20), timeout: 120, handle: handle)
        // The child holds the pipe as its stdin (`<&0`) for 10 minutes: a writer that blocked would hold the run as long.
        #expect(Date().timeIntervalSince(start) < 120)
        #expect(out.stdout.range(of: Data("done".utf8)) != nil)
        // By the time the run returns, its input was given up and the pipe closed: nothing left writing.
        #expect(handle.isInputClosed)
    }
}

