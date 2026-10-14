import Foundation

/// What a computer's agent tools (Node.js and the Claude Code CLI) look like to a person.
enum AgentToolsAdvice {
    static func needsSetup(_ status: SiloWireAgentToolsStatus) -> Bool { status.state != .ready }

    static func actionTitle(_ status: SiloWireAgentToolsStatus) -> String {
        status.state == .outdated ? "Update" : "Set up"
    }

    static func toolName(_ id: String) -> String {
        switch id {
        case "node": "Node.js"
        case "claude": "Claude Code"
        default: id
        }
    }

    static func missingNames(_ status: SiloWireAgentToolsStatus) -> [String] {
        status.missing.map(toolName)
    }

    static func headline(_ status: SiloWireAgentToolsStatus) -> String {
        switch status.state {
        case .ready: "Ready"
        case .missing: "Missing"
        case .outdated: "Update available"
        }
    }

    static func detail(_ status: SiloWireAgentToolsStatus) -> String {
        switch status.state {
        case .ready:
            return versions(status)
        case .missing:
            let names = missingNames(status)
            let list = names.isEmpty ? "Node.js and Claude Code" : names.joined(separator: " and ")
            return "\(list) \(names.count > 1 || names.isEmpty ? "aren't" : "isn't") installed in this computer."
        case .outdated:
            return "\(versions(status)). Silo now ships Node.js \(status.expectedNodeVersion) and Claude Code \(status.expectedClaudeVersion)."
        }
    }

    private static func versions(_ status: SiloWireAgentToolsStatus) -> String {
        "Node.js \(status.nodeVersion ?? "?") · Claude Code \(status.claudeVersion ?? "?")"
    }

    /// Why a run or a session start stops before it begins.
    static func blocked(_ status: SiloWireAgentToolsStatus, computerName: String) -> String {
        "\(computerName) needs its agent tools \(status.state == .outdated ? "updated" : "set up") (\(detail(status))) "
            + "Open it in Computers and use \(actionTitle(status))."
    }
}

enum AgentToolsFailure: LocalizedError, Equatable {
    case macOSNeedsSetup(String)
    case setupFailed(String)
    case stillNotReady(String)

    var errorDescription: String? {
        switch self {
        case .macOSNeedsSetup(let name):
            "\(name) is a Mac computer: Silo installs its agent tools with its developer-tools setup. Open it in Computers and retry its setup, then try again."
        case .setupFailed(let reason): "Setting up the agent tools failed: \(reason)"
        case .stillNotReady(let name): "\(name)'s agent tools still aren't ready after the setup finished. Check its activity log in Computers."
        }
    }
}

/// Checks a computer's agent tools and, when asked, sets them up as an engine job before a run needs them.
@MainActor
struct AgentToolsSetup {
    let engine: any EngineClient
    var pollInterval: Duration = .milliseconds(250)
    var pollLimit = 8_000

    /// Nil when the engine cannot inspect the computer (a stopped Linux computer).
    func status(_ target: GuestReference) async throws -> SiloWireAgentToolsStatus? {
        let status: SiloWireDesktopStatus = try await engine.invoke(SiloGeneratedMethods.desktopStatus(
            SiloWireComputerTargetParams(computerId: target.computerId, deviceId: target.deviceId)))
        return status.agentTools
    }

    /// Runs `setup-agent-tools` and waits for the job; returns the status afterwards.
    @discardableResult
    func setUp(_ target: GuestReference, computerName: String,
               progress: @MainActor (String) async -> Void = { _ in }) async throws -> SiloWireAgentToolsStatus? {
        await progress("Setting up Node.js and Claude Code in \(computerName)")
        let started: SiloWireJobStartResult = try await engine.invoke(SiloGeneratedMethods.desktopAction(
            SiloWireDesktopActionParams(action: .setupAgentTools, computerId: target.computerId, deviceId: target.deviceId)))
        let began = Date()
        for _ in 0..<pollLimit {
            let snapshot = try await engine.operationsJobGet(jobId: started.jobId, deviceId: target.deviceId)
            if snapshot.state == .finished {
                if let error = snapshot.outcome?.error { throw AgentToolsFailure.setupFailed(error.userMessage) }
                try? await engine.operationsJobAcknowledge(jobId: started.jobId, deviceId: target.deviceId)
                return try await status(target)
            }
            let seconds = Int(Date().timeIntervalSince(began))
            await progress("Setting up Node.js and Claude Code in \(computerName) (\(seconds) s)")
            try await Task.sleep(for: pollInterval)
        }
        throw AgentToolsFailure.setupFailed("The job didn't finish in time.")
    }

    /// The gate before a run: ready tools pass; otherwise they are set up first (Linux) or the run is refused with
    /// the way forward (Mac computers, which Silo sets up with the developer-tools step).
    func ensureReady(_ target: GuestReference, kind: ComputerKind, computerName: String,
                     progress: @MainActor (String) async -> Void = { _ in }) async throws {
        guard let current = try await status(target), AgentToolsAdvice.needsSetup(current) else { return }
        guard kind == .linux else { throw AgentToolsFailure.macOSNeedsSetup(computerName) }
        let after = try await setUp(target, computerName: computerName, progress: progress)
        if let after, AgentToolsAdvice.needsSetup(after) { throw AgentToolsFailure.stillNotReady(computerName) }
    }
}
