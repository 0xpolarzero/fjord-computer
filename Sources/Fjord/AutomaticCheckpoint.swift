import Foundation

/// The checkpoint taken before a Triage action starts a session in a computer (95-decisions A-18): the last few per computer
/// are kept, each labeled as automatic, and a setting changes the count or turns them off.
enum AutomaticCheckpoint {
    static let suffix = ", deleted automatically"

    struct Failure: LocalizedError {
        var errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Keeps the required automatic marker and fits Silo's printable 1–80 character checkpoint name limit.
    static func label(task: String) -> String {
        let clean = task.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init).joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let lead = "Before run: "
        let room = max(0, 80 - lead.count - suffix.count)
        let bounded = String(clean.prefix(room)).trimmingCharacters(in: .whitespacesAndNewlines)
        let label = lead + (bounded.isEmpty ? "task" : bounded) + suffix
        return String(label.prefix(80))
    }

    /// Saves the checkpoint and waits until Silo says it is done. Returns its name, or nil when automatic checkpoints are
    /// off (the owner's count is 0). Throws, with the reason, when the setting can't be read or the checkpoint isn't made:
    /// the session is then not started.
    @MainActor
    static func take(engine: any EngineClient, computer: GuestReference, task: String,
                     pollEvery: Duration = .milliseconds(250), attempts: Int = 1_200) async throws -> String? {
        let retention: UInt64
        do {
            let snapshot: SiloWireSettingsSnapshot = try await engine.invoke(SiloGeneratedMethods.settingsRead(SiloWireEmptyParams()))
            retention = snapshot.settings.automaticCheckpointRetentionCount ?? 3
        } catch {
            throw Failure("Fjord couldn't read the automatic checkpoint setting: \(error.localizedDescription)")
        }
        guard retention > 0 else { return nil }
        let name = label(task: task)
        let job: ComputerJob
        do {
            job = try await engine.checkpointsCreate(CheckpointCreateRequest(
                computerId: computer.computerId, deviceId: computer.deviceId, kind: .automatic, name: name))
        } catch {
            throw Failure("Fjord couldn't save the checkpoint before the session (\(error.localizedDescription)). The session was not started.")
        }
        for _ in 0..<attempts {
            let snapshot: OperationJobSnapshot
            do { snapshot = try await engine.operationsJobGet(jobId: job.jobId, deviceId: computer.deviceId) }
            catch {
                throw Failure("Fjord lost the checkpoint's result (\(error.localizedDescription)). The session was not started.")
            }
            if snapshot.state == .finished {
                if let failed = snapshot.outcome?.error {
                    throw Failure("The checkpoint before the session failed: \(failed.userMessage). The session was not started.")
                }
                try? await engine.operationsJobAcknowledge(jobId: job.jobId, deviceId: computer.deviceId)
                return name
            }
            try await Task.sleep(for: pollEvery)
        }
        throw Failure("The checkpoint before the session didn't finish in time. The session was not started.")
    }
}
