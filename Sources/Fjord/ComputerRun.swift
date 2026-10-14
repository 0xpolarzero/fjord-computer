import AppKit
import CryptoKit
import Foundation

/// A rule's fixed placement and reviewed execution policy. A Triage run never picks a computer by name or by repo path.
struct RunInComputerSettings: Codable, Hashable, Sendable {
    var deviceID: String?
    var computerID: String
    var computerName: String
    /// Explicit guest workspace root. Fjord appends the validated GitHub repository name without resolving it on the host.
    var workspaceRoot: String
    var promptTemplate: String
    var model: String?
    var effort: String?
    var permissionMode: PermissionMode = .default
    var allowedTools: [String] = []
    var recordProof = true

    enum PermissionMode: String, Codable, CaseIterable, Hashable, Sendable {
        case `default` = "default"
        case plan
        case acceptEdits

        var title: String {
            switch self {
            case .default: "Default permissions"
            case .plan: "Plan only"
            case .acceptEdits: "Accept edits"
            }
        }
    }

    var target: GuestReference { GuestReference(deviceId: deviceID, computerId: computerID) }

    func repositoryPath(repo: String) throws -> String {
        guard let validRepo = InboxActions.trustedRepo(repo), validRepo == repo,
              workspaceRoot.hasPrefix("/"), !workspaceRoot.contains("\0"),
              Self.safeSegments(workspaceRoot),
              repo.split(separator: "/").last.map(String.init).map({ $0 != "." && $0 != ".." }) == true else {
            throw ComputerRunFailure.invalidPlacement
        }
        let root = workspaceRoot == "/" ? "" : workspaceRoot.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name = repo.split(separator: "/").last.map(String.init) ?? ""
        guard !name.isEmpty else { throw ComputerRunFailure.invalidPlacement }
        return root.isEmpty ? "/\(name)" : "/\(root)/\(name)"
    }

    func validate() throws {
        guard !computerID.isEmpty, !computerID.contains("\0"),
              !computerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !computerName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              workspaceRoot.hasPrefix("/"), !workspaceRoot.contains("\0"),
              Self.safeSegments(workspaceRoot),
              !promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              promptTemplate.utf8.count <= 20_000,
              workspaceRoot.utf8.count <= 4_096,
              allowedTools.count <= 64,
              allowedTools.allSatisfy({ tool in
                  tool.utf8.count <= 200 && !tool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !tool.hasPrefix("-")
                      && !tool.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
              }),
              model == nil || ActionSettings.clean(model, in: ActionSettings.models) == model,
              effort == nil || ActionSettings.clean(effort, in: ActionSettings.efforts) == effort else {
            throw ComputerRunFailure.invalidPlacement
        }
    }

    private static func safeSegments(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: true).allSatisfy { segment in
            segment != "." && segment != ".."
                && !segment.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }
    }
}

enum ComputerRunPhase: String, Codable, Hashable, Sendable {
    case preflight, startingComputer, preparingWorkspace, checkpointing, recording, running, finalizingProof
    case result, failed, cancelled, unconfirmed

    var title: String {
        switch self {
        case .preflight: "Checking the computer"
        case .startingComputer: "Starting the computer"
        case .preparingWorkspace: "Preparing the repository"
        case .checkpointing: "Saving the checkpoint"
        case .recording: "Starting proof recording"
        case .running: "Claude is running"
        case .finalizingProof: "Finalizing proof"
        case .result: "Run complete"
        case .failed: "Run failed"
        case .cancelled: "Run cancelled"
        case .unconfirmed: "Run outcome unconfirmed"
        }
    }

    var isEngineOwnedActive: Bool {
        switch self {
        case .startingComputer, .preparingWorkspace, .checkpointing, .recording, .running, .finalizingProof: true
        case .preflight, .result, .failed, .cancelled, .unconfirmed: false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .result, .failed, .cancelled: true
        case .preflight, .startingComputer, .preparingWorkspace, .checkpointing, .recording, .running, .finalizingProof, .unconfirmed: false
        }
    }
}

enum ComputerRunProofState: String, Codable, Hashable, Sendable {
    case notRequested, notStarted, starting, complete, partial, failed
}

enum ComputerRunTerminalState: String, Codable, Hashable, Sendable {
    case exited, cancelled, lost
}

/// Durable Triage projection. The Engine job owns execution; this record lets Fjord reattach without launching it again.
struct ComputerRunRecord: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var categoryID: UUID
    var actionID: UUID
    var thingID: String
    var triggerKey: String
    var deviceID: String?
    var computerID: String
    var computerName: String
    var repo: String
    var repositoryPath: String
    var branch: String
    var taskTitle: String
    var promptFingerprint: String
    var phase: ComputerRunPhase = .preflight
    var detail = ""
    /// Stable client-side workflow identity. The current generated checkpoints.create schema has no idempotency field.
    var checkpointOperationID: UUID
    var startJobID: String? = nil
    var checkpointJobID: String?
    var checkpointID: String?
    var automaticCheckpointSkipped: Bool? = nil
    /// User cancellation requested before the guest Claude job was admitted.
    var cancellationRequested: Bool? = nil
    /// Stable client-side workflow identity. The current generated guest.exec.start schema has no idempotency field.
    var execOperationID: UUID
    var execJobID: String?
    var execSequence: UInt64 = 0
    var summary: String?
    var summaryUnverified = true
    var exitCode: Int32?
    var taskReportedError: Bool?
    var terminalState: ComputerRunTerminalState?
    var pullRequestURL: URL?
    var proofRequested: Bool
    var proofState: ComputerRunProofState
    var guestVideoPath: String?
    var localVideoPath: String?
    var videoDurationSeconds: Double?
    var presented = false
    var acknowledged = false
    var checkpointAcknowledged: Bool?
    var execAcknowledged: Bool?
    var rollbackOperationID: UUID?
    var rollbackJobID: String?
    var rolledBackAt: Date?
    var rollbackError: String?
    var startedAt: Date
    var updatedAt: Date

    init(id: UUID, categoryID: UUID, actionID: UUID, thingID: String, triggerKey: String,
         settings: RunInComputerSettings, repo: String, repositoryPath: String, branch: String,
         taskTitle: String, prompt: String, now: Date = Date()) {
        self.id = id
        self.categoryID = categoryID
        self.actionID = actionID
        self.thingID = thingID
        self.triggerKey = triggerKey
        deviceID = settings.deviceID
        computerID = settings.computerID
        computerName = settings.computerName
        self.repo = repo
        self.repositoryPath = repositoryPath
        self.branch = branch
        self.taskTitle = taskTitle
        promptFingerprint = ComputerRunPrompt.fingerprint(prompt)
        checkpointOperationID = UUID()
        execOperationID = UUID()
        proofRequested = settings.recordProof
        proofState = settings.recordProof ? .starting : .notRequested
        startedAt = now
        updatedAt = now
    }
}

enum ComputerRunFailure: LocalizedError, Equatable {
    case invalidPlacement
    case gateClosed(String)
    case cancellationRequested
    case computerUnavailable(String)
    case workspace(String)
    case job(String)
    case proof(String)
    case unconfirmed(String)
    case result(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlacement: "Choose a computer, an absolute workspace root, and a non-empty prompt."
        case .cancellationRequested: "Cancellation was requested before the guest job was admitted."
        case .gateClosed(let reason), .computerUnavailable(let reason), .workspace(let reason), .job(let reason),
             .proof(let reason), .unconfirmed(let reason), .result(let reason): reason
        }
    }
}

enum ComputerRunGit {
    enum CheckoutBase {
        case freshClone
        case afterFetch

        var revision: String {
            switch self {
            case .freshClone: "HEAD"
            case .afterFetch: "FETCH_HEAD"
            }
        }
    }

    static func createRunBranchArguments(path: String, branch: String, from base: CheckoutBase) -> [String] {
        ["-C", path, "switch", "-c", branch, base.revision]
    }
}

enum ComputerRunCheckpointLabel {
    static let suffix = ", deleted automatically"

    /// Keeps the required automatic marker and fits Silo's printable 1–80 character checkpoint name limit.
    static func make(task: String) -> String {
        let clean = task.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init).joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let lead = "Before run: "
        let room = max(0, 80 - lead.count - suffix.count)
        let bounded = String(clean.prefix(room)).trimmingCharacters(in: .whitespacesAndNewlines)
        let label = lead + (bounded.isEmpty ? "task" : bounded) + suffix
        return String(label.prefix(80))
    }
}

enum ComputerRunPrompt {
    static func fingerprint(_ prompt: String) -> String {
        SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func render(_ template: String, thing: Thing) -> String {
        let values: [(String, String, Int)] = [
            ("{title}", thing.title, 200),
            ("{url}", thing.url.absoluteString, 500),
            ("{number}", thing.number.map(String.init) ?? "", 20),
            ("{repo}", thing.repo, 200),
            ("{author}", thing.author.map { "@" + $0.login } ?? "", 120),
        ]
        let rendered = values.reduce(template) { prompt, field in
            let data = UntrustedText.clean(field.1, limit: field.2)
            return prompt.replacingOccurrences(of: field.0, with: UntrustedFence.github.fence(data))
        }
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func branch(task: String, runID: UUID) -> String {
        let slug = task.lowercased().unicodeScalars.map { scalar -> Character in
            (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57)
                ? Character(String(scalar)) : "-"
        }
        let compact = String(String(slug).split(separator: "-").joined(separator: "-").prefix(36)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "fjord/triage/\(compact.isEmpty ? "task" : compact)-\(runID.uuidString.prefix(8).lowercased())"
    }
}

struct ComputerRunParsedResult: Equatable {
    var summary: String?
    var isError: Bool
    var pullRequestURL: URL?
    var hasFinalResult: Bool
}

enum ComputerRunResultParser {
    static func parse(_ data: Data, repo: String) -> ComputerRunParsedResult {
        let text = String(decoding: data, as: UTF8.self)
        var summary: String?
        var isError = false
        var hasFinalResult = false
        for line in text.split(whereSeparator: \.isNewline) {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  row["type"] as? String == "result",
                  let result = row["result"] as? String,
                  let resultIsError = row["is_error"] as? Bool else { continue }
            let clean = UntrustedText.clean(result, limit: 1_200)
            guard !clean.isEmpty else { continue }
            summary = clean
            isError = resultIsError
            hasFinalResult = true
        }
        let pr = pullRequest(in: summary ?? "", repo: repo)
        return ComputerRunParsedResult(summary: summary, isError: isError, pullRequestURL: pr,
                                       hasFinalResult: hasFinalResult)
    }

    private static func pullRequest(in text: String, repo: String) -> URL? {
        guard let range = text.range(of: #"https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]{1,12}"#, options: .regularExpression),
              let url = URL(string: String(text[range])),
              url.absoluteString.lowercased().hasPrefix("https://github.com/\(repo.lowercased())/pull/") else { return nil }
        return url
    }
}

actor LocalComputerRunArtifactStore {
    var root: URL? = nil

    init(root: URL? = nil) { self.root = root }

    func saveVideo(_ data: Data, runID: UUID) throws -> URL {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fjord/TriageRuns", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("\(runID.uuidString.lowercased()).mp4")
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum ComputerRunGate {
    static let tokenName = "CLAUDE_CODE_OAUTH_TOKEN"
    static let allowedAuthDomain = "api.anthropic.com"
    /// A saved Silo secret can supply the placeholder, but B-17 did not qualify OAuth Bearer substitution.
    static let productionBlocker = "Gated: Claude OAuth Bearer substitution is unproven (B-17). Fjord will not start an unattended Claude run until a controlled Bearer check and harmless authenticated request pass."
}

enum ComputerRunResource {
    static func data(named name: String) throws -> Data {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("GuestRuns", isDirectory: true).appendingPathComponent(name)
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/GuestRuns", isDirectory: true)
            .appendingPathComponent(name)
        for url in [bundled, sourceRoot].compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        throw ComputerRunFailure.proof("The guest run helper is missing from this Fjord build.")
    }
}

/// One serial workflow for a selected computer. The release gate is injectable only to make each stage testable against mocks.
@MainActor
final class ComputerRunCoordinator {
    enum Authorization { case qualified, blocked(String) }

    private static var activeComputers = Set<String>()
    private static var restoredComputers = Set<String>()
    private let engine: any EngineClient
    private let guest: any GuestClient
    private let authorization: Authorization
    private let checkpointRetentionOverride: UInt64?
    private let secretAssignmentOverride: Bool?
    private let githubRepositoryOverride: Bool?
    private let linuxDesktopStatusOverride: SiloWireDesktopStatus?
    private let shouldContinue: @MainActor () -> Bool
    private let cancellationRequested: @MainActor () -> Bool
    private let progressWriter: @MainActor (ComputerRunRecord, String, Date) async -> Bool
    private let artifacts: LocalComputerRunArtifactStore

    static func isActive(on target: GuestReference) -> Bool {
        activeComputers.contains(target.key) || restoredComputers.contains(target.key)
    }

    static func isExecuting(on target: GuestReference) -> Bool { activeComputers.contains(target.key) }

    static func reserveRestoredTarget(_ target: GuestReference) {
        guard !activeComputers.contains(target.key) else { return }
        restoredComputers.insert(target.key)
    }

    init(engine: any EngineClient, guest: any GuestClient, authorization: Authorization,
         checkpointRetentionCount: UInt64? = nil, secretAssignment: Bool? = nil, githubRepository: Bool? = nil,
         linuxDesktopStatus: SiloWireDesktopStatus? = nil,
         shouldContinue: @escaping @MainActor () -> Bool = { true },
         cancellationRequested: @escaping @MainActor () -> Bool = { false },
         progressWriter: @escaping @MainActor (ComputerRunRecord, String, Date) async -> Bool = { _, _, _ in true },
         artifacts: LocalComputerRunArtifactStore? = nil) {
        self.engine = engine
        self.guest = guest
        self.authorization = authorization
        checkpointRetentionOverride = checkpointRetentionCount
        secretAssignmentOverride = secretAssignment
        githubRepositoryOverride = githubRepository
        linuxDesktopStatusOverride = linuxDesktopStatus
        self.shouldContinue = shouldContinue
        self.cancellationRequested = cancellationRequested
        self.progressWriter = progressWriter
        self.artifacts = artifacts ?? LocalComputerRunArtifactStore()
    }

    func run(_ initial: ComputerRunRecord, settings: RunInComputerSettings, thing: Thing,
             persist: @escaping @MainActor (ComputerRunRecord) async -> Bool) async throws -> ComputerRunRecord {
        var record = initial
        let key = GuestReference(deviceId: record.deviceID, computerId: record.computerID).key
        guard !Self.restoredComputers.contains(key), Self.activeComputers.insert(key).inserted else {
            throw ComputerRunFailure.job("Another Triage run is already active on \(record.computerName).")
        }
        defer { Self.activeComputers.remove(key) }

        do {
            try await transition(&record, .preflight, ComputerRunGateText.preflight, persist: persist)
            switch authorization {
            case .qualified: break
            case .blocked(let reason): throw ComputerRunFailure.gateClosed(reason)
            }
            try settings.validate()
            let retention = try await automaticCheckpointRetention()
            try await requireAuthSecret(target: settings.target)
            guard let repo = InboxActions.trustedRepo(thing.repo), repo == thing.repo else {
                throw ComputerRunFailure.workspace("The GitHub repository name is invalid.")
            }
            try await requireGitHubAccess(repo: repo, target: settings.target)

            let inventory = try await engine.computersList(deviceId: settings.deviceID)
            guard let computer = inventory.computer(settings.computerID) else {
                // Never falls back to a computer with the same id on another owner: ids are owner-local.
                throw ComputerRunFailure.computerUnavailable("\(record.computerName) is no longer in the inventory of \(settings.deviceID.map { "device \($0)" } ?? "This Mac"). Choose a computer again.")
            }
            try requireCurrentAction()
            var lifecycleSubscription: String?
            let progressSink = ComputerRunProgressSink(record: record, persist: progressWriter)
            do {
                lifecycleSubscription = try await engine.eventsSubscribe(events: ["operations.job.progress", "operations.job.finished",
                                                                                   "guest.exec.output", "guest.exec.exited"]) { delivery in
                    progressSink.receive(delivery)
                }
            } catch {
                throw ComputerRunFailure.computerUnavailable("Fjord couldn't subscribe to computer job events: \(error.localizedDescription)")
            }
            defer {
                progressSink.stop()
                if let lifecycleSubscription {
                    Task { @MainActor in await self.engine.eventsUnsubscribe(subscription: lifecycleSubscription) }
                }
            }

            if computer.displayState != .running {
                try await transition(&record, .startingComputer, "Starting \(record.computerName)", persist: persist)
                let job: ComputerJob
                do {
                    job = try await engine.computersStart(ComputerReference(computerId: record.computerID, deviceId: record.deviceID))
                } catch {
                    throw ComputerRunFailure.computerUnavailable(error.localizedDescription)
                }
                record.startJobID = job.jobId
                progressSink.record = record
                guard await persist(record) else {
                    throw ComputerRunFailure.unconfirmed("Silo accepted the start job, but Fjord couldn't save its job id.")
                }
                try await cancelIfRequested(record, jobID: job.jobId)
                _ = try await requireSuccessfulJob(job.jobId, deviceID: record.deviceID)
                try requireCurrentAction()
            }

            let account: GuestAccount
            do { account = try await guest.account(for: settings.target) }
            catch { throw ComputerRunFailure.computerUnavailable(error.localizedDescription) }
            try await requireAgentTools(record: record, target: settings.target, kind: account.operatingSystem)
            let linuxDisplay: String?
            if settings.recordProof, account.operatingSystem == .linux {
                linuxDisplay = try await requireLinuxDesktopReady(target: settings.target)
            } else {
                linuxDisplay = nil
            }

            let repoPath = try settings.repositoryPath(repo: repo)
            guard repoPath == record.repositoryPath else {
                throw ComputerRunFailure.invalidPlacement
            }
            try await transition(&record, .preparingWorkspace, "Cloning or fetching \(repo)", persist: persist)
            try requireCurrentAction()
            try await prepareWorkspace(repo: repo, path: repoPath, root: settings.workspaceRoot, branch: record.branch,
                                       computer: settings.target)
            try requireCurrentAction()

            if retention > 0 {
                let checkpointName = ComputerRunCheckpointLabel.make(task: record.taskTitle)
                let before = try await engine.checkpointsList(computerId: record.computerID, deviceId: record.deviceID)
                let beforeIDs = Set(before.map(\.id))
                record.checkpointOperationID = UUID()
                try await transition(&record, .checkpointing, "Saving \(checkpointName)", persist: persist)
                try requireCurrentAction()
                let checkpointJob: ComputerJob
                do {
                    checkpointJob = try await engine.checkpointsCreate(CheckpointCreateRequest(
                        computerId: record.computerID, deviceId: record.deviceID, kind: .automatic, name: checkpointName))
                } catch {
                    record.phase = .unconfirmed
                    record.detail = "Checkpoint acceptance is uncertain; the task was not started. \(error.localizedDescription)"
                    _ = await persist(record)
                    throw ComputerRunFailure.unconfirmed(record.detail)
                }
                record.checkpointJobID = checkpointJob.jobId
                progressSink.record = record
                guard await persist(record) else { throw ComputerRunFailure.job("Fjord couldn't save the checkpoint job id; the task was not started.") }
                try await cancelIfRequested(record, jobID: checkpointJob.jobId)
                let checkpointSnapshot = try await requireSuccessfulJob(checkpointJob.jobId, deviceID: record.deviceID)
                record.checkpointID = Self.checkpointID(from: checkpointSnapshot.outcome?.result)
                if record.checkpointID == nil {
                    let after = try await engine.checkpointsList(computerId: record.computerID, deviceId: record.deviceID)
                    record.checkpointID = after.first { !beforeIDs.contains($0.id) && $0.name == checkpointName }?.id
                }
                guard record.checkpointID != nil else {
                    throw ComputerRunFailure.unconfirmed("The checkpoint job finished, but Silo did not return its checkpoint id. The task was not started.")
                }
                guard await persist(record) else { throw ComputerRunFailure.job("Fjord couldn't save the checkpoint id; the task was not started.") }
                progressSink.record = record
                try requireCurrentAction()
            } else {
                record.automaticCheckpointSkipped = true
                try await transition(&record, .checkpointing, "Automatic checkpoints off", persist: persist)
                try requireCurrentAction()
            }

            let prompt = ComputerRunPrompt.render(settings.promptTemplate, thing: thing)
            guard !prompt.isEmpty else { throw ComputerRunFailure.result("The rendered task prompt is empty.") }
            guard account.home.hasPrefix("/"), !account.home.contains("\0") else {
                throw ComputerRunFailure.computerUnavailable("The guest returned an invalid home folder.")
            }
            let home = account.home == "/" ? "" : account.home.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let controlRoot = (home.isEmpty ? "" : "/\(home)") + "/.fjord/runs/\(record.id.uuidString.lowercased())"
            let proofRoot = "\(controlRoot)/proof"
            let helperPath = "\(controlRoot)/run.mjs"
            let configPath = "\(controlRoot)/run.json"
            let videoPath = "\(proofRoot)/proof.mp4"
            let manifestPath = "\(proofRoot)/manifest.json"
            record.guestVideoPath = settings.recordProof ? videoPath : nil

            try await transition(&record, settings.recordProof ? .recording : .running,
                                 settings.recordProof ? "Preparing guest proof recorder" : "Starting headless Claude",
                                 persist: persist)
            try requireCurrentAction()
            let supervisor = try ComputerRunResource.data(named: "run.mjs")
            let helperWrite = GuestFileWriteRequest(computer: settings.target, path: helperPath, data: supervisor,
                                                    mode: 0o700, createParents: true, replace: .always)
            _ = try await guest.filesWrite(helperWrite)
            if account.operatingSystem == .macos, settings.recordProof {
                try requireCurrentAction()
                let recorder = try ComputerRunResource.data(named: "GuestRecorder.app.zip")
                _ = try await guest.filesWrite(GuestFileWriteRequest(computer: settings.target,
                    path: "\(controlRoot)/GuestRecorder.app.zip", data: recorder, mode: 0o600,
                    createParents: true, replace: .always))
            }
            let config = ComputerRunSupervisorConfig(
                runID: record.id.uuidString.lowercased(), platform: account.operatingSystem.rawValue, home: account.home,
                node: account.nodeExecutable, claude: account.claudeExecutable, cwd: repoPath, prompt: prompt,
                model: settings.model, effort: settings.effort, permissionMode: settings.permissionMode.rawValue,
                allowedTools: settings.allowedTools, recordProof: settings.recordProof,
                display: linuxDisplay, videoPath: videoPath, manifestPath: manifestPath,
                recorderArchivePath: "\(controlRoot)/GuestRecorder.app.zip")
            let configData = try JSONEncoder().encode(config)
            try requireCurrentAction()
            _ = try await guest.filesWrite(GuestFileWriteRequest(computer: settings.target, path: configPath,
                data: configData, mode: 0o600, createParents: true, replace: .always))

            record.execOperationID = UUID()
            let argv = [account.nodeExecutable, helperPath, configPath]
            let jobID: String
            try requireCurrentAction()
            do {
                jobID = try await guest.execStart(GuestExecStartRequest(computer: settings.target, argv: argv,
                    cwd: repoPath, retainOutputBytes: 1024 * 1024))
            } catch {
                record.phase = .unconfirmed
                record.detail = "Fjord couldn't confirm whether Silo admitted the headless Claude job. It will not submit a duplicate. \(error.localizedDescription)"
                record.updatedAt = Date()
                _ = await persist(record)
                throw ComputerRunFailure.unconfirmed(record.detail)
            }
            record.execJobID = jobID
            progressSink.record = record
            guard await persist(record) else {
                record.phase = .unconfirmed
                record.detail = "Silo accepted the guest job, but Fjord couldn't save its job id. It will not launch a duplicate."
                _ = await persist(record)
                throw ComputerRunFailure.unconfirmed(record.detail)
            }
            try await cancelIfRequested(record, jobID: jobID)
            record.phase = .running
            record.detail = settings.recordProof ? "Recorder ready; Claude started on branch \(record.branch)" : "Claude started on branch \(record.branch)"
            record.updatedAt = Date()
            progressSink.record = record
            guard await persist(record) else {
                record.phase = .unconfirmed
                record.detail = "The engine accepted the run, but Fjord couldn't save its job id. It will not launch a duplicate."
                _ = await persist(record)
                throw ComputerRunFailure.unconfirmed(record.detail)
            }

            let completed = try await collectGuestJob(jobID, computer: settings.target, record: &record, persist: persist)
            return try await finishGuestJob(completed, record: &record, repo: repo, persist: persist)
        } catch {
            if record.proofRequested && record.proofState == .starting && record.phase != .unconfirmed {
                record.proofState = .notStarted
            }
            if record.phase != .result && record.phase != .cancelled && record.phase != .failed {
                if cancellationRequested() || error as? ComputerRunFailure == .cancellationRequested {
                    record.phase = .cancelled
                    record.detail = error.localizedDescription
                } else if let failure = error as? ComputerRunFailure, case .unconfirmed = failure {
                    record.phase = .unconfirmed
                    record.detail = error.localizedDescription
                } else if record.phase != .unconfirmed {
                    record.phase = .failed
                    record.detail = error.localizedDescription
                }
                record.updatedAt = Date()
                _ = await persist(record)
            }
            throw error
        }
    }

    /// Reattach to the persisted guest job after Fjord restarts. This path never submits a new guest.exec.start.
    func reattach(_ initial: ComputerRunRecord,
                  persist: @escaping @MainActor (ComputerRunRecord) async -> Bool) async throws -> ComputerRunRecord {
        guard let jobID = initial.execJobID else {
            throw ComputerRunFailure.unconfirmed("Fjord has no saved guest job id for this run and will not submit a duplicate.")
        }
        let key = GuestReference(deviceId: initial.deviceID, computerId: initial.computerID).key
        guard Self.activeComputers.insert(key).inserted else { return initial }
        Self.restoredComputers.remove(key)
        defer { Self.activeComputers.remove(key) }
        var record = initial
        let target = GuestReference(deviceId: record.deviceID, computerId: record.computerID)
        let progressSink = ComputerRunProgressSink(record: record, persist: progressWriter)
        let subscription: String?
        do {
            subscription = try await engine.eventsSubscribe(events: ["operations.job.progress", "operations.job.finished",
                                                                      "guest.exec.output", "guest.exec.exited"]) { delivery in
                progressSink.receive(delivery)
            }
        } catch {
            subscription = nil
        }
        defer {
            progressSink.stop()
            if let subscription {
                Task { @MainActor in await self.engine.eventsUnsubscribe(subscription: subscription) }
            }
        }

        do {
            if record.summary != nil, record.exitCode != nil {
                let state: GuestExecJobState = switch record.terminalState {
                case .cancelled: .cancelled
                case .lost: .lost
                case .exited, .none: .exited
                }
                let terminal = GuestExecJobResult(state: state, exitCode: record.exitCode, stdout: Data(), stderr: Data(),
                                                  nextSequence: record.execSequence)
                return try await finishGuestJob(terminal, record: &record, repo: record.repo, persist: persist)
            }
            let completed = try await collectGuestJob(jobID, computer: target, record: &record, persist: persist)
            return try await finishGuestJob(completed, record: &record, repo: record.repo, persist: persist)
        } catch {
            if record.phase != .result && record.phase != .cancelled && record.phase != .failed && record.phase != .unconfirmed {
                record.phase = .unconfirmed
                record.detail = error.localizedDescription
                record.updatedAt = Date()
                _ = await persist(record)
            }
            throw error
        }
    }

    private func finishGuestJob(_ completed: GuestExecJobResult, record: inout ComputerRunRecord,
                                repo: String,
                                persist: @escaping @MainActor (ComputerRunRecord) async -> Bool) async throws -> ComputerRunRecord {
        let parsed: ComputerRunParsedResult
        if completed.stdout.isEmpty, let summary = record.summary {
            parsed = ComputerRunParsedResult(summary: summary, isError: record.taskReportedError == true,
                pullRequestURL: record.pullRequestURL, hasFinalResult: true)
        } else {
            parsed = ComputerRunResultParser.parse(completed.stdout, repo: repo)
        }
        record.summary = parsed.summary
        record.pullRequestURL = parsed.pullRequestURL
        record.taskReportedError = parsed.hasFinalResult ? parsed.isError : nil
        record.exitCode = completed.exitCode ?? record.exitCode
        record.terminalState = switch completed.state {
        case .exited: .exited
        case .cancelled: .cancelled
        case .lost: .lost
        case .running: nil
        }
        record.summaryUnverified = true
        record.execSequence = max(record.execSequence, completed.nextSequence)

        guard completed.state == .exited else {
            if completed.state == .cancelled {
                record.phase = .finalizingProof
                record.detail = "The headless job was cancelled; retrieving any finalized proof."
                _ = await persist(record)
                if record.proofRequested {
                    let target = GuestReference(deviceId: record.deviceID, computerId: record.computerID)
                    if let artifact = try? await readProofArtifact(record, target: target),
                       let localVideo = try? await artifacts.saveVideo(artifact.bytes, runID: record.id) {
                        record.localVideoPath = localVideo.path
                        record.proofState = .partial
                        record.videoDurationSeconds = artifact.duration
                    } else {
                        record.proofState = .failed
                    }
                }
                record.phase = .cancelled
                record.detail = "The headless job was cancelled."
                record.updatedAt = Date()
                _ = await persist(record)
                throw ComputerRunFailure.job(record.detail)
            }
            record.phase = .unconfirmed
            record.detail = "The engine lost this run before it reported a terminal result."
            _ = await persist(record)
            throw ComputerRunFailure.unconfirmed(record.detail)
        }

        try await transition(&record, .finalizingProof, "Claude finished; retrieving the guest result", persist: persist)
        var proofFailure: String?
        if record.proofRequested {
            let target = GuestReference(deviceId: record.deviceID, computerId: record.computerID)
            do {
                let artifact = try await readProofArtifact(record, target: target)
                let localVideo = try await artifacts.saveVideo(artifact.bytes, runID: record.id)
                record.localVideoPath = localVideo.path
                record.proofState = .complete
                record.videoDurationSeconds = artifact.duration
            } catch {
                record.proofState = .failed
                proofFailure = error.localizedDescription
            }
        }

        guard completed.exitCode == 0, record.taskReportedError != true else {
            record.phase = .failed
            record.detail = "Claude reported an error or exited with code \(completed.exitCode ?? -1)."
            if let proofFailure { record.detail += " Proof recording also failed: \(proofFailure)" }
            _ = await persist(record)
            throw ComputerRunFailure.result(record.detail)
        }
        guard parsed.hasFinalResult else {
            record.phase = .failed
            record.summary = nil
            record.taskReportedError = nil
            record.detail = "Claude exited without a valid structured final result."
            if let proofFailure { record.detail += " Proof recording also failed: \(proofFailure)" }
            record.updatedAt = Date()
            _ = await persist(record)
            throw ComputerRunFailure.result(record.detail)
        }
        record.phase = .result
        record.detail = "Run complete on \(record.branch). Claude's summary is unverified by Fjord."
        if record.automaticCheckpointSkipped == true { record.detail += " Automatic checkpoints off." }
        if let proofFailure { record.detail += " Proof recording failed: \(proofFailure)" }
        record.updatedAt = Date()
        guard await persist(record) else { throw ComputerRunFailure.job("The result exists, but Fjord couldn't save the completed run record.") }
        return record
    }

    private func readProofArtifact(_ record: ComputerRunRecord, target: GuestReference) async throws -> (bytes: Data, duration: Double?) {
        guard let videoPath = record.guestVideoPath, let slash = videoPath.lastIndex(of: "/") else {
            throw ComputerRunFailure.proof("The guest video path was not saved.")
        }
        let manifestPath = String(videoPath[..<slash]) + "/manifest.json"
        let manifest = try await guest.filesRead(computer: target, path: manifestPath, offset: nil, length: nil)
        guard let value = try? JSONSerialization.jsonObject(with: manifest.data) as? [String: Any] else {
            throw ComputerRunFailure.proof("The guest recorder returned an unreadable proof manifest.")
        }
        guard value["state"] as? String == "complete",
              value["runID"] as? String == record.id.uuidString.lowercased(),
              value["videoPath"] as? String == videoPath else {
            let detail = (value["error"] as? String).map { ": \(UntrustedText.clean($0, limit: 300))" } ?? ""
            throw ComputerRunFailure.proof("The guest recorder did not confirm a complete movie\(detail).")
        }
        let bytes = try await readGuestFile(videoPath, computer: target)
        guard let expectedBytes = value["bytes"] as? NSNumber, expectedBytes.int64Value == Int64(bytes.count) else {
            throw ComputerRunFailure.proof("The guest video size does not match its finalized proof manifest.")
        }
        return (bytes, value["durationSeconds"] as? Double)
    }

    func rollback(_ record: ComputerRunRecord, persist: @escaping @MainActor (ComputerRunRecord) async -> Bool) async throws -> ComputerRunRecord {
        var changed = record
        guard !record.phase.isEngineOwnedActive, record.phase != .unconfirmed else {
            throw ComputerRunFailure.job("Wait for the guest run to reach a confirmed result before restoring its checkpoint.")
        }
        guard record.rollbackOperationID == nil, record.rollbackJobID == nil, record.rolledBackAt == nil else {
            throw ComputerRunFailure.job("A rollback is already pending or complete.")
        }
        guard let checkpointID = record.checkpointID else { throw ComputerRunFailure.job("This run has no checkpoint to restore.") }
        let key = GuestReference(deviceId: record.deviceID, computerId: record.computerID).key
        guard !Self.restoredComputers.contains(key), Self.activeComputers.insert(key).inserted else {
            throw ComputerRunFailure.job("Another Triage operation is active on \(record.computerName).")
        }
        defer { Self.activeComputers.remove(key) }
        changed.rollbackOperationID = UUID()
        changed.rollbackError = nil
        changed.updatedAt = Date()
        guard await persist(changed) else {
            changed.rollbackOperationID = nil
            changed.rollbackError = "Fjord couldn't save the rollback request; no restore was submitted."
            changed.updatedAt = Date()
            if !(await persist(changed)) { Self.restoredComputers.insert(key) }
            throw ComputerRunFailure.job("Fjord couldn't save the rollback request.")
        }
        var restoreAccepted = false
        var confirmedJobFailure = false
        do {
            let job = try await engine.checkpointsRestore(CheckpointRestoreRequest(
                checkpointId: checkpointID, computerId: record.computerID, deviceId: record.deviceID))
            restoreAccepted = true
            changed.rollbackJobID = job.jobId
            changed.updatedAt = Date()
            guard await persist(changed) else {
                changed.rollbackError = "Rollback was accepted, but Fjord couldn't save its job id. It will not submit another restore."
                changed.updatedAt = Date()
                _ = await persist(changed)
                Self.restoredComputers.insert(key)
                throw ComputerRunFailure.unconfirmed(
                    "Rollback was accepted, but Fjord couldn't save its job id. It will not submit another restore.")
            }
            do {
                _ = try await requireSuccessfulJob(job.jobId, deviceID: record.deviceID)
            } catch {
                if Self.isFinishedRollbackFailure(error) { confirmedJobFailure = true }
                throw error
            }
            changed.rolledBackAt = Date()
            changed.updatedAt = Date()
            guard await persist(changed) else {
                changed.rolledBackAt = nil
                changed.rollbackError = "The restore finished, but Fjord couldn't save its result. It will not submit another restore."
                changed.updatedAt = Date()
                _ = await persist(changed)
                Self.restoredComputers.insert(key)
                throw ComputerRunFailure.unconfirmed(
                    "The restore finished, but Fjord couldn't save its result. It will not submit another restore.")
            }
            return changed
        } catch {
            let confirmedRejection = !restoreAccepted && Self.isConfirmedRestoreRejection(error)
            let canRetry = confirmedRejection || confirmedJobFailure
            let failure: Error
            if canRetry {
                changed.rollbackOperationID = nil
                changed.rollbackJobID = nil
                failure = error
            } else if !restoreAccepted, !(error is ComputerRunFailure) {
                failure = ComputerRunFailure.unconfirmed(
                    "Fjord couldn't confirm whether Silo accepted the rollback. It will not submit a duplicate. \(error.localizedDescription)")
            } else {
                failure = error
            }
            changed.rollbackError = failure.localizedDescription
            changed.updatedAt = Date()
            let saved = await persist(changed)
            if !canRetry || !saved { Self.restoredComputers.insert(key) }
            throw failure
        }
    }

    /// Reconcile an accepted rollback after relaunch without submitting another restore.
    func reattachRollback(_ initial: ComputerRunRecord,
                          persist: @escaping @MainActor (ComputerRunRecord) async -> Bool) async throws -> ComputerRunRecord {
        guard initial.rollbackOperationID != nil, initial.rolledBackAt == nil,
              let jobID = initial.rollbackJobID else {
            throw ComputerRunFailure.unconfirmed("Fjord has no saved restore job id and will not submit a duplicate rollback.")
        }
        let key = GuestReference(deviceId: initial.deviceID, computerId: initial.computerID).key
        guard Self.activeComputers.insert(key).inserted else { return initial }
        Self.restoredComputers.remove(key)
        defer { Self.activeComputers.remove(key) }

        var changed = initial
        var confirmedJobFailure = false
        do {
            do {
                _ = try await requireSuccessfulJob(jobID, deviceID: initial.deviceID)
            } catch {
                if Self.isFinishedRollbackFailure(error) { confirmedJobFailure = true }
                throw error
            }
            changed.rolledBackAt = Date()
            changed.rollbackError = nil
            changed.updatedAt = Date()
            guard await persist(changed) else {
                changed.rolledBackAt = nil
                changed.rollbackError = "The restore finished, but Fjord couldn't save its result. It will not submit another restore."
                changed.updatedAt = Date()
                _ = await persist(changed)
                Self.restoredComputers.insert(key)
                throw ComputerRunFailure.unconfirmed(
                    "The restore finished, but Fjord couldn't save its result. It will not submit another restore.")
            }
            return changed
        } catch {
            if confirmedJobFailure {
                changed.rollbackOperationID = nil
                changed.rollbackJobID = nil
            }
            changed.rollbackError = error.localizedDescription
            changed.updatedAt = Date()
            let saved = await persist(changed)
            if !confirmedJobFailure || !saved { Self.restoredComputers.insert(key) }
            if confirmedJobFailure, saved { return changed }
            throw error
        }
    }

    private static func isConfirmedRestoreRejection(_ error: Error) -> Bool {
        guard let error = error as? EngineClientError else { return false }
        switch error {
        case .notFound, .unsupported, .invalidAction, .jobFailed, .coded: return true
        case .unavailable: return false
        }
    }

    private static func isFinishedRollbackFailure(_ error: Error) -> Bool {
        guard let error = error as? ComputerRunFailure, case .job = error else { return false }
        return true
    }

    private func prepareWorkspace(repo: String, path: String, root: String, branch: String,
                                  computer: GuestReference) async throws {
        let mkdir = try await guest.exec(GuestExecRequest(computer: computer, argv: ["mkdir", "-p", root], cwd: "/", timeoutSeconds: 20))
        guard mkdir.succeeded else { throw ComputerRunFailure.workspace("Couldn't prepare the workspace folder: \(Self.output(mkdir.stderr))") }
        let probe = try await guest.exec(GuestExecRequest(computer: computer,
            argv: ["git", "-C", path, "rev-parse", "--is-inside-work-tree"], cwd: root, timeoutSeconds: 20))
        let checkoutBase: ComputerRunGit.CheckoutBase
        if probe.succeeded {
            let remote = try await guest.exec(GuestExecRequest(computer: computer,
                argv: ["git", "-C", path, "remote", "get-url", "origin"], cwd: root, timeoutSeconds: 20))
            guard remote.succeeded, let address = String(data: remote.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  LocalClones.repo(fromRemote: address)?.lowercased() == repo.lowercased() else {
                throw ComputerRunFailure.workspace("The selected guest folder is not a clone of \(repo).")
            }
            let fetch = try await guest.exec(GuestExecRequest(computer: computer,
                argv: ["git", "-C", path, "fetch", "--depth=1", "origin", "HEAD"], cwd: root, timeoutSeconds: 180))
            guard fetch.succeeded else { throw ComputerRunFailure.workspace("Git fetch failed: \(Self.output(fetch.stderr))") }
            checkoutBase = .afterFetch
        } else {
            let clone = try await guest.exec(GuestExecRequest(computer: computer,
                argv: ["git", "clone", "--depth=1", "https://github.com/\(repo).git", path], cwd: root,
                timeoutSeconds: 300))
            guard clone.succeeded else { throw ComputerRunFailure.workspace("Git clone failed: \(Self.output(clone.stderr))") }
            checkoutBase = .freshClone
        }
        let checkout = try await guest.exec(GuestExecRequest(computer: computer,
            argv: ["git"] + ComputerRunGit.createRunBranchArguments(path: path, branch: branch, from: checkoutBase),
            cwd: root, timeoutSeconds: 30))
        guard checkout.succeeded else { throw ComputerRunFailure.workspace("Couldn't create the run branch: \(Self.output(checkout.stderr))") }
    }

    private func collectGuestJob(_ jobID: String, computer: GuestReference, record: inout ComputerRunRecord,
                                 persist: @escaping @MainActor (ComputerRunRecord) async -> Bool) async throws -> GuestExecJobResult {
        var sequence = record.execSequence
        var stdout = Data()
        var stderr = Data()
        var state = GuestExecJobResult(state: .running, exitCode: nil, stdout: Data(), stderr: Data(), nextSequence: sequence)
        for _ in 0..<14_400 {
            do {
                state = try await guest.execGet(computer: computer, jobId: jobID, sinceSequence: sequence)
            } catch {
                throw ComputerRunFailure.unconfirmed("Fjord lost the guest job connection. The saved job id remains available for reattachment; no replacement task was submitted. \(error.localizedDescription)")
            }
            if state.nextSequence < sequence {
                stdout.append(Data("\n[Earlier output unavailable]\n".utf8))
            }
            stdout.append(state.stdout)
            stderr.append(state.stderr)
            if stdout.count > 2 * 1024 * 1024 { stdout = stdout.suffix(2 * 1024 * 1024) }
            if stderr.count > 512 * 1024 { stderr = stderr.suffix(512 * 1024) }
            sequence = max(sequence, state.nextSequence)
            record.updatedAt = Date()
            if !state.stdout.isEmpty || !state.stderr.isEmpty {
                record.detail = "Claude is running · \(sequence) output events read"
                _ = await persist(record)
            }
            if state.state != .running { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard state.state != .running else { throw ComputerRunFailure.unconfirmed("The guest job did not finish within one hour.") }
        // Output is parsed in memory only. Secret values are never copied into actions.json or diagnostics.
        state.stdout = stdout
        state.stderr = stderr
        state.nextSequence = sequence
        return state
    }

    private func readGuestFile(_ path: String, computer: GuestReference) async throws -> Data {
        let chunk = 512 * 1024
        var offset: Int64 = 0
        var output = Data()
        var identity: (size: Int64, inode: Int64, mtime: Int64)?
        while identity.map({ offset < $0.size }) ?? true {
            let part = try await guest.filesRead(computer: computer, path: path, offset: offset, length: chunk)
            if identity == nil { identity = (part.size, part.inode, part.mtimeMs) }
            guard let first = identity, part.size == first.size, part.inode == first.inode, part.mtimeMs == first.mtime else {
                throw ComputerRunFailure.proof("The guest video changed while Fjord retrieved it.")
            }
            guard first.size <= 64 * 1024 * 1024, !part.data.isEmpty else {
                throw ComputerRunFailure.proof("The guest video is empty or exceeds the 64 MiB retrieval limit.")
            }
            output.append(part.data)
            offset += Int64(part.data.count)
        }
        return output
    }

    private func requireSuccessfulJob(_ jobID: String, deviceID: String?) async throws -> OperationJobSnapshot {
        for _ in 0..<1_200 {
            let snapshot: OperationJobSnapshot
            do {
                snapshot = try await engine.operationsJobGet(jobId: jobID, deviceId: deviceID)
            } catch {
                throw ComputerRunFailure.unconfirmed("Silo accepted job \(jobID), but Fjord lost its durable result connection. It will not submit a duplicate. \(error.localizedDescription)")
            }
            if snapshot.state == .finished {
                if let error = snapshot.outcome?.error { throw ComputerRunFailure.job(error.userMessage) }
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw ComputerRunFailure.unconfirmed("Silo accepted job \(jobID), but it did not report a durable result before the deadline.")
    }

    private func transition(_ record: inout ComputerRunRecord, _ phase: ComputerRunPhase, _ detail: String,
                            persist: @escaping @MainActor (ComputerRunRecord) async -> Bool) async throws {
        record.phase = phase
        record.detail = detail
        record.updatedAt = Date()
        guard await persist(record) else { throw ComputerRunFailure.job("Fjord couldn't durably save the \(phase.title.lowercased()) state. No next mutation was made.") }
    }

    private func requireCurrentAction() throws {
        if cancellationRequested() { throw ComputerRunFailure.cancellationRequested }
        guard shouldContinue() else {
            throw ComputerRunFailure.gateClosed("The Triage rule or its trigger changed before the guest run started.")
        }
    }

    private func cancelIfRequested(_ record: ComputerRunRecord, jobID: String?) async throws {
        guard cancellationRequested() else { return }
        if let jobID {
            try? await engine.operationsCancel(jobId: jobID, deviceId: record.deviceID)
        }
        throw ComputerRunFailure.cancellationRequested
    }

    /// Node.js and the Claude Code CLI must be in the computer before the workspace is touched: missing or outdated tools
    /// are set up here as a job (Linux), with their progress as the run's detail, rather than failing in the guest later.
    private func requireAgentTools(record: ComputerRunRecord, target: GuestReference, kind: ComputerKind) async throws {
        do {
            try await AgentToolsSetup(engine: engine).ensureReady(target, kind: kind, computerName: record.computerName) { message in
                _ = await self.progressWriter(record, message, Date())
            }
        } catch let failure as AgentToolsFailure {
            throw ComputerRunFailure.computerUnavailable(failure.localizedDescription)
        } catch {
            throw ComputerRunFailure.computerUnavailable("Fjord couldn't check the agent tools in \(record.computerName): \(error.localizedDescription)")
        }
    }

    private func requireLinuxDesktopReady(target: GuestReference) async throws -> String {
        var status: SiloWireDesktopStatus
        if let linuxDesktopStatusOverride {
            status = linuxDesktopStatusOverride
        } else {
            do {
                status = try await engine.invoke(SiloGeneratedMethods.desktopStatus(
                    SiloWireComputerTargetParams(computerId: target.computerId, deviceId: target.deviceId)))
            } catch {
                throw ComputerRunFailure.proof("Fjord couldn't verify the Linux desktop before recording: \(error.localizedDescription)")
            }
        }
        guard status.installed else {
            throw ComputerRunFailure.proof("Install the Linux desktop service before enabling proof video for this computer.")
        }
        if Self.linuxDesktopIsReady(status), let display = status.display { return display }
        // An explicit proof-video opt-in authorizes starting an already installed guest desktop service.
        // Injected status keeps unit tests deterministic and does not simulate an engine-side service transition.
        guard linuxDesktopStatusOverride == nil else {
            throw ComputerRunFailure.proof("Start the Linux desktop service and wait for its session before running with proof video.")
        }
        do {
            let started: SiloWireJobStartResult = try await engine.invoke(SiloGeneratedMethods.desktopAction(
                SiloWireDesktopActionParams(action: .start, computerId: target.computerId, deviceId: target.deviceId)))
            _ = try await requireSuccessfulJob(started.jobId, deviceID: target.deviceId)
        } catch {
            throw ComputerRunFailure.proof("Fjord couldn't start the Linux desktop service for proof recording: \(error.localizedDescription)")
        }
        for _ in 0..<120 {
            do {
                status = try await engine.invoke(SiloGeneratedMethods.desktopStatus(
                    SiloWireComputerTargetParams(computerId: target.computerId, deviceId: target.deviceId)))
            } catch {
                throw ComputerRunFailure.proof("Fjord couldn't verify the Linux desktop after starting it: \(error.localizedDescription)")
            }
            if Self.linuxDesktopIsReady(status), let display = status.display { return display }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw ComputerRunFailure.proof("The Linux desktop service did not reach a recording-ready session within one minute.")
    }

    private static func linuxDesktopIsReady(_ status: SiloWireDesktopStatus) -> Bool {
        status.installed && status.state == "running" && status.sessionState == "running"
            && status.display?.range(of: #"^:[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil
    }

    private func automaticCheckpointRetention() async throws -> UInt64 {
        if let checkpointRetentionOverride { return checkpointRetentionOverride }
        do {
            let snapshot: SiloWireSettingsSnapshot = try await engine.invoke(
                SiloGeneratedMethods.settingsRead(SiloWireEmptyParams()))
            return snapshot.settings.automaticCheckpointRetentionCount ?? 3
        } catch {
            throw ComputerRunFailure.gateClosed("Fjord couldn't read the owner's automatic checkpoint setting: \(error.localizedDescription)")
        }
    }

    private func requireAuthSecret(target: GuestReference) async throws {
        if let secretAssignmentOverride {
            guard secretAssignmentOverride else {
                throw ComputerRunFailure.gateClosed("Save and assign the \(ComputerRunGate.tokenName) secret to this computer in Computers → Secrets before running.")
            }
            return
        }
        do {
            let secrets: [SiloWireSecret] = try await engine.invoke(
                SiloGeneratedMethods.secretsList(SiloWireDeviceParams(deviceId: target.deviceId)))
            guard let secret = secrets.first(where: { $0.name == ComputerRunGate.tokenName }),
                  secret.computerIds.contains(target.computerId), secret.state == .active,
                  !secret.removing, !secret.pendingComputerIds.contains(target.computerId) else {
                throw ComputerRunFailure.gateClosed("Save and assign an active \(ComputerRunGate.tokenName) secret to this computer in Computers → Secrets before running.")
            }
            guard secret.allowedDomains.contains(ComputerRunGate.allowedAuthDomain) else {
                throw ComputerRunFailure.gateClosed("The \(ComputerRunGate.tokenName) secret must allow \(ComputerRunGate.allowedAuthDomain).")
            }
        } catch let failure as ComputerRunFailure {
            throw failure
        } catch {
            throw ComputerRunFailure.gateClosed("Fjord couldn't verify the computer's Claude token secret: \(error.localizedDescription)")
        }
    }

    private func requireGitHubAccess(repo: String, target: GuestReference) async throws {
        if let githubRepositoryOverride {
            guard githubRepositoryOverride else {
                throw ComputerRunFailure.workspace("Grant this computer access to \(repo) in Computers → GitHub before running.")
            }
            return
        }
        do {
            let state: SiloWireGitHubState = try await engine.invoke(
                SiloGeneratedMethods.githubState(SiloWireDeviceParams(deviceId: target.deviceId)))
            guard state.accessEnabled, state.state == .connected,
                  let policy = state.computers.first(where: { $0.computerId == target.computerId }) else {
                throw ComputerRunFailure.workspace("Connect GitHub and grant this computer access to \(repo) in Computers → GitHub.")
            }
            let allowed = policy.repositoryMode == .all || policy.repositories.contains {
                $0.repository.caseInsensitiveCompare(repo) == .orderedSame
            }
            guard allowed else {
                throw ComputerRunFailure.workspace("Grant this computer access to \(repo) in Computers → GitHub.")
            }
        } catch let failure as ComputerRunFailure {
            throw failure
        } catch {
            throw ComputerRunFailure.workspace("Fjord couldn't verify GitHub access for \(repo): \(error.localizedDescription)")
        }
    }

    private static func checkpointID(from value: JSONValue?) -> String? {
        guard case .object(let object)? = value else { return nil }
        for key in ["checkpoint", "checkpointCreated", "checkpoint_created"] {
            guard case .object(let checkpoint)? = object[key] else { continue }
            if case .string(let id)? = checkpoint["id"] { return id }
        }
        return nil
    }

    private static func output(_ data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(400))
    }
}

@MainActor
private final class ComputerRunProgressSink {
    var record: ComputerRunRecord
    private let persist: @MainActor (ComputerRunRecord, String, Date) async -> Bool
    private var active = true

    init(record: ComputerRunRecord, persist: @escaping @MainActor (ComputerRunRecord, String, Date) async -> Bool) {
        self.record = record
        self.persist = persist
    }

    func receive(_ delivery: EngineEventDelivery) {
        guard active else { return }
        if case .sequenceAdvanced = delivery, record.execJobID != nil {
            record.detail = "Guest job event received; reading the run output"
            record.updatedAt = Date()
            let copy = record
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                _ = await self.persist(copy, copy.detail, copy.updatedAt)
            }
            return
        }
        guard case .event(_, let event) = delivery else { return }
        switch event {
        case .jobProgress(let progress, _) where matches(progress.jobId):
            guard let text = progress.data.presentationTitle else { return }
            record.detail = text
        case .jobFinished(let finished, _) where matches(finished.jobId):
            record.detail = "Job finished; reading its durable result"
        default:
            return
        }
        record.updatedAt = Date()
        let copy = record
        Task { @MainActor [weak self] in
            guard let self, self.active else { return }
            _ = await self.persist(copy, copy.detail, copy.updatedAt)
        }
    }

    func stop() { active = false }

    private func matches(_ jobID: String) -> Bool {
        jobID == record.checkpointJobID || jobID == record.execJobID || jobID == record.rollbackJobID
    }
}

private enum ComputerRunGateText { static let preflight = "Checking authorization and the selected computer" }

private struct ComputerRunSupervisorConfig: Encodable {
    var runID: String
    var platform: String
    var home: String
    var node: String
    var claude: String
    var cwd: String
    var prompt: String
    var model: String?
    var effort: String?
    var permissionMode: String
    var allowedTools: [String]
    var recordProof: Bool
    var display: String?
    var videoPath: String
    var manifestPath: String
    var recorderArchivePath: String
}

@MainActor
extension Store {
    func resumeComputerRun(_ id: UUID) async {
        guard let record = actionLedger.computerRuns[id],
              record.phase.isEngineOwnedActive || record.phase == .unconfirmed else { return }
        let target = GuestReference(deviceId: record.deviceID, computerId: record.computerID)
        guard !ComputerRunCoordinator.isExecuting(on: target) else { return }
        guard record.execJobID != nil else {
            guard record.phase != .unconfirmed else { return }
            var uncertain = record
            uncertain.phase = .unconfirmed
            uncertain.detail = "Fjord restarted before it saved a guest job id. It will not submit a duplicate."
            uncertain.updatedAt = Date()
            _ = await saveComputerRun(uncertain)
            return
        }
        let guest: any GuestClient
        if let registered = GuestRouterRuntime.shared.guestClient(for: record.location) {
            guest = registered
        } else if let socket = engineClient as? SocketEngineClient {
            guest = SiloGuestClient(engine: socket)
        } else {
            return
        }
        let coordinator = ComputerRunCoordinator(engine: engineClient, guest: guest,
            authorization: .blocked(ComputerRunGate.productionBlocker),
            cancellationRequested: { [weak self] in
                self?.actionLedger.computerRuns[id]?.cancellationRequested == true
            },
            progressWriter: { [weak self] source, detail, updatedAt in
                guard let self else { return false }
                return await self.saveComputerRunProgress(source, detail: detail, updatedAt: updatedAt)
            })
        do {
            _ = try await coordinator.reattach(record) { [weak self] updated in
                guard let self else { return false }
                return await self.saveComputerRun(updated)
            }
        } catch { }
    }

    func resumeComputerRunRollback(_ id: UUID) async {
        guard let record = actionLedger.computerRuns[id], record.rollbackOperationID != nil,
              record.rollbackJobID != nil, record.rolledBackAt == nil else { return }
        let target = GuestReference(deviceId: record.deviceID, computerId: record.computerID)
        guard !ComputerRunCoordinator.isExecuting(on: target) else { return }
        let guest: any GuestClient
        if let registered = GuestRouterRuntime.shared.guestClient(for: record.location) {
            guest = registered
        } else if let socket = engineClient as? SocketEngineClient {
            guest = SiloGuestClient(engine: socket)
        } else {
            return
        }
        let coordinator = ComputerRunCoordinator(engine: engineClient, guest: guest,
            authorization: .blocked(ComputerRunGate.productionBlocker))
        do {
            _ = try await coordinator.reattachRollback(record) { [weak self] updated in
                guard let self else { return false }
                return await self.saveComputerRunRollback(updated)
            }
        } catch { }
    }

    func computerRunIsCurrent(_ record: ComputerRunRecord, settings: RunInComputerSettings) -> Bool {
        guard triageOn, computersOn, !baselinePending, !onDefaults, let me = me?.login, !me.isEmpty,
              let category = categories.first(where: { $0.id == record.categoryID }),
              let baseline = actionLedger.baselines[record.categoryID],
              baseline.rules == InboxActions.fingerprint(category.rules, groups: groups),
              baseline.actions.contains(record.actionID),
              let action = category.actions.items.first(where: { $0.id == record.actionID }),
              case .runInComputer(let currentSettings) = action.kind, currentSettings == settings,
              let entry = entries.first(where: { $0.id == record.thingID && $0.categoryID == record.categoryID && !$0.isDone }) else {
            return false
        }
        let currentPrompt = ComputerRunPrompt.render(settings.promptTemplate, thing: entry.thing)
        guard ComputerRunPrompt.fingerprint(currentPrompt) == record.promptFingerprint else { return false }
        let claimed = actionLedger.runs.values.filter { $0.computerRunID == record.id && $0.state == .running }
        switch action.trigger {
        case .enter:
            return claimed.contains { $0.trigger == "enter" }
        case .eachFact:
            let currentFacts = Set(InboxActions.triggering(entry, me: me).map(\.key))
            return claimed.contains { $0.trigger != "enter" && currentFacts.contains($0.trigger) }
        }
    }

    func saveComputerRun(_ record: ComputerRunRecord) async -> Bool {
        var saved = record
        if let current = actionLedger.computerRuns[record.id] {
            let incomingWins: Bool
            if current.phase.isTerminal {
                incomingWins = record.phase == current.phase && record.updatedAt >= current.updatedAt
            } else {
                incomingWins = record.updatedAt >= current.updatedAt
            }
            let other = incomingWins ? current : record
            saved = incomingWins ? record : current
            saved.startJobID = saved.startJobID ?? other.startJobID
            saved.checkpointJobID = saved.checkpointJobID ?? other.checkpointJobID
            saved.checkpointID = saved.checkpointID ?? other.checkpointID
            saved.automaticCheckpointSkipped = saved.automaticCheckpointSkipped ?? other.automaticCheckpointSkipped
            saved.execJobID = saved.execJobID ?? other.execJobID
            saved.localVideoPath = saved.localVideoPath ?? other.localVideoPath
            saved.rolledBackAt = saved.rolledBackAt ?? other.rolledBackAt
            let confirmsRollbackFailure = incomingWins && record.rollbackOperationID == nil
                && record.rollbackJobID == nil && record.rollbackError != nil
                && current.rollbackOperationID != nil && current.rolledBackAt == nil
            let beginsRollbackRetry = incomingWins && record.rollbackOperationID != nil
                && record.rollbackOperationID != current.rollbackOperationID
            if confirmsRollbackFailure {
                saved.rollbackOperationID = nil
                saved.rollbackJobID = nil
                saved.rollbackError = record.rollbackError
            } else {
                saved.rollbackOperationID = saved.rollbackOperationID ?? other.rollbackOperationID
                saved.rollbackJobID = saved.rollbackJobID ?? other.rollbackJobID
                if beginsRollbackRetry {
                    saved.rollbackError = record.rollbackError
                } else {
                    saved.rollbackError = saved.rollbackError ?? other.rollbackError
                }
            }
            saved.presented = record.presented || current.presented
            saved.acknowledged = record.acknowledged || current.acknowledged
            saved.checkpointAcknowledged = record.checkpointAcknowledged == true || current.checkpointAcknowledged == true
                ? true : record.checkpointAcknowledged ?? current.checkpointAcknowledged
            saved.execAcknowledged = record.execAcknowledged == true || current.execAcknowledged == true
                ? true : record.execAcknowledged ?? current.execAcknowledged
            saved.cancellationRequested = record.cancellationRequested == true || current.cancellationRequested == true
                ? true : record.cancellationRequested ?? current.cancellationRequested
        }
        actionLedger.computerRuns[record.id] = saved
        return await actionsWritten()
    }

    func saveComputerRunRollback(_ source: ComputerRunRecord) async -> Bool {
        guard var current = actionLedger.computerRuns[source.id], current.phase == source.phase,
              current.checkpointID == source.checkpointID, current.execJobID == source.execJobID else { return false }
        let startsNewAttempt = current.rollbackOperationID == nil && source.rollbackOperationID != nil
            && source.rollbackError == nil
        let confirmsFailure = source.rollbackOperationID == nil && source.rollbackJobID == nil
            && source.rollbackError != nil && current.rollbackOperationID != nil && current.rolledBackAt == nil
        guard current.rollbackOperationID == source.rollbackOperationID
                || startsNewAttempt || confirmsFailure else { return false }
        current.rollbackOperationID = source.rollbackOperationID
        current.rollbackJobID = source.rollbackJobID
        current.rolledBackAt = source.rolledBackAt
        current.rollbackError = source.rollbackError
        current.updatedAt = max(current.updatedAt, source.updatedAt)
        actionLedger.computerRuns[source.id] = current
        return await actionsWritten()
    }

    func saveComputerRunProgress(_ source: ComputerRunRecord, detail: String, updatedAt: Date) async -> Bool {
        guard var current = actionLedger.computerRuns[source.id], !current.phase.isTerminal,
              current.phase == source.phase,
              current.startJobID == source.startJobID,
              current.checkpointJobID == source.checkpointJobID,
              current.execJobID == source.execJobID,
              current.rollbackJobID == source.rollbackJobID else { return true }
        current.detail = detail
        current.updatedAt = max(current.updatedAt, updatedAt)
        actionLedger.computerRuns[source.id] = current
        return await actionsWritten()
    }

    func rollbackComputerRun(_ id: UUID) async {
        guard let record = actionLedger.computerRuns[id] else { return }
        guard record.rollbackOperationID == nil, record.rollbackJobID == nil, record.rolledBackAt == nil else { return }
        guard !record.phase.isEngineOwnedActive, record.phase != .unconfirmed else {
            actionLedger.computerRuns[id]?.rollbackError = "Wait for the guest run to reach a confirmed result before restoring its checkpoint."
            return
        }
        let guest: any GuestClient
        if let registered = GuestRouterRuntime.shared.guestClient(for: record.location) {
            guest = registered
        } else if let socket = engineClient as? SocketEngineClient {
            guest = SiloGuestClient(engine: socket)
        } else {
            var failed = record
            failed.rollbackError = "No guest client is available for this computer."
            actionLedger.computerRuns[id] = failed
            return
        }
        let coordinator = ComputerRunCoordinator(engine: engineClient, guest: guest, authorization: .qualified)
        do {
            let changed = try await coordinator.rollback(record) { [weak self] updated in
                guard let self else { return false }
                return await self.saveComputerRunRollback(updated)
            }
            if let current = actionLedger.computerRuns[id], let jobID = current.rollbackJobID,
               current.rollbackOperationID == changed.rollbackOperationID {
                do {
                    try await engineClient.operationsJobAcknowledge(jobId: jobID, deviceId: current.deviceID)
                    if actionLedger.computerRuns[id]?.rollbackJobID == jobID {
                        actionLedger.computerRuns[id]?.acknowledged = true
                        _ = await actionsWritten()
                    }
                } catch { }
            }
        } catch {
            guard var latest = actionLedger.computerRuns[id] else { return }
            latest.rollbackError = error.localizedDescription
            latest.updatedAt = Date()
            actionLedger.computerRuns[id] = latest
            _ = await actionsWritten()
        }
    }

    func openComputerRunInClaude(_ id: UUID) async {
        guard let record = actionLedger.computerRuns[id],
              let guest = GuestRouterRuntime.shared.guestClient(for: record.location)
                ?? (engineClient as? SocketEngineClient).map({ SiloGuestClient(engine: $0) }) else { return }
        do {
            let alias = try await guest.sshAliasEnsure(computer: GuestReference(deviceId: record.deviceID, computerId: record.computerID), installInclude: true)
            try ClaudeSSHSettings().install(.init(deviceId: record.deviceID, computerId: record.computerID,
                                                  computerName: record.computerName, ownerName: alias.ownerName, alias: alias.alias))
            let prompt = "Review the Triage run on branch \(record.branch): \(record.taskTitle)"
            if let url = GuestDesktopStart.deepLink(alias: alias.alias, folder: record.repositoryPath, prompt: prompt) {
                Link.open(url)
            }
        } catch { }
    }

    func acknowledgeComputerRun(_ id: UUID) async {
        guard var record = actionLedger.computerRuns[id] else { return }
        record.presented = true
        actionLedger.computerRuns[id] = record
        guard await saveComputerRun(record) else { return }
        var checkpointAcknowledged = record.checkpointAcknowledged == true
        var execAcknowledged = record.execAcknowledged == true
        if let jobID = record.checkpointJobID, record.checkpointAcknowledged != true,
           record.checkpointID != nil || record.phase.isTerminal {
            do {
                try await engineClient.operationsJobAcknowledge(jobId: jobID, deviceId: record.deviceID)
                checkpointAcknowledged = true
            } catch { }
        }
        if let jobID = record.execJobID, record.phase.isTerminal, record.execAcknowledged != true {
            do {
                try await engineClient.operationsJobAcknowledge(jobId: jobID, deviceId: record.deviceID)
                execAcknowledged = true
            } catch { }
        }
        guard var latest = actionLedger.computerRuns[id] else { return }
        latest.presented = true
        if checkpointAcknowledged { latest.checkpointAcknowledged = true }
        if execAcknowledged { latest.execAcknowledged = true }
        latest.acknowledged = (latest.checkpointJobID == nil || latest.checkpointAcknowledged == true)
            && (latest.execJobID == nil || latest.execAcknowledged == true)
        actionLedger.computerRuns[id] = latest
        _ = await actionsWritten()
    }

    func cancelComputerRun(_ id: UUID) async {
        guard var record = actionLedger.computerRuns[id],
              record.phase.isEngineOwnedActive || record.phase == .unconfirmed else { return }
        record.cancellationRequested = true
        let jobID: String?
        switch record.phase {
        case .startingComputer: jobID = record.startJobID
        case .checkpointing: jobID = record.checkpointJobID ?? record.startJobID
        case .recording, .running, .finalizingProof: jobID = record.execJobID
        case .unconfirmed: jobID = record.execJobID ?? record.checkpointJobID ?? record.startJobID
        case .preflight, .preparingWorkspace, .result, .failed, .cancelled: jobID = nil
        }
        if jobID != nil {
            record.detail = "Cancellation requested; waiting for the current guest operation to stop."
        } else {
            record.detail = "Cancellation requested; no guest job has been admitted."
        }
        record.updatedAt = Date()
        actionLedger.computerRuns[id] = record
        guard await saveComputerRun(record), let jobID else { return }
        guard let latest = actionLedger.computerRuns[id], !latest.phase.isTerminal else { return }
        do {
            try await engineClient.operationsCancel(jobId: jobID, deviceId: record.deviceID)
        } catch {
            guard var latest = actionLedger.computerRuns[id], !latest.phase.isTerminal else { return }
            latest.detail = "Cancellation request could not be confirmed: \(error.localizedDescription)"
            latest.updatedAt = Date()
            actionLedger.computerRuns[id] = latest
            _ = await actionsWritten()
        }
    }
}

extension ComputerRunRecord {
    var location: SessionLocation { .computer(deviceId: deviceID, computerId: computerID) }
}
