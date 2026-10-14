import Darwin
import Foundation

private enum SocketClientFailure: LocalizedError {
    case socket(String)
    case frameTooLarge
    case malformed(String)
    case closed
    case incompatibleVersion(Int, SiloWireProtocolRange)
    case remote(String, String)

    var errorDescription: String? {
        switch self {
        case .socket(let message): message
        case .frameTooLarge: "The Silo frame exceeds the 4 MiB limit."
        case .malformed(let message): "Invalid Silo response: \(message)"
        case .closed: "The Silo socket is closed."
        case .incompatibleVersion(let version, let range):
            "Silo negotiated protocol \(version), outside Fjord's supported range \(range.min)…\(range.max)."
        case .remote(_, let message): message
        }
    }

    var engineError: Error {
        switch self {
        case .remote(let code, let message):
            switch code {
            case "not_found": EngineClientError.notFound(message)
            case "unsupported_remote_operation", "incompatible_version": EngineClientError.unsupported(message)
            case "changed", "already_queued", "busy": EngineClientError.invalidAction(message)
            default: EngineClientError.jobFailed(message)
            }
        case .incompatibleVersion(_, _): EngineClientError.unsupported(errorDescription ?? "Incompatible Silo protocol.")
        default: self
        }
    }
}

private final class UnixDomainSocket: @unchecked Sendable {
    private static let maximumFrameBytes = 4 * 1024 * 1024
    private let descriptor: Int32

    init(path: String) throws {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Self.systemFailure("create socket") }
        descriptor = fd

        var noSigPipe: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        let pathBytes = Array(path.utf8)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < pathCapacity else {
            Darwin.close(fd)
            throw SocketClientFailure.socket("Unix socket path is too long.")
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        pathBytes.withUnsafeBytes { source in
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                destination.initializeMemory(as: UInt8.self, repeating: 0)
                destination.copyBytes(from: source)
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let failure = Self.systemFailure("connect \(path)")
            Darwin.close(fd)
            throw failure
        }
    }

    deinit { Darwin.close(descriptor) }

    func shutdown() { _ = Darwin.shutdown(descriptor, SHUT_RDWR) }

    func writeFrame(_ json: Data) throws {
        guard !json.isEmpty, json.count <= Self.maximumFrameBytes else { throw SocketClientFailure.frameTooLarge }
        let length = UInt32(json.count)
        var frame = Data([
            UInt8((length >> 24) & 0xff), UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff), UInt8(length & 0xff),
        ])
        frame.append(json)
        try frame.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.send(descriptor, base.advanced(by: offset), buffer.count - offset, 0)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw Self.systemFailure("write frame")
                }
                guard written > 0 else { throw SocketClientFailure.closed }
                offset += written
            }
        }
    }

    func readFrame() throws -> Data? {
        guard let header = try readExactly(4, allowEOF: true) else { return nil }
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= Self.maximumFrameBytes else { throw SocketClientFailure.frameTooLarge }
        return try readExactly(Int(length), allowEOF: false)
    }

    private func readExactly(_ length: Int, allowEOF: Bool) throws -> Data? {
        var data = Data(count: length)
        var received = 0
        var reachedEOF = false
        try data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            while received < length {
                let amount = Darwin.recv(descriptor, base.advanced(by: received), length - received, 0)
                if amount < 0 {
                    if errno == EINTR { continue }
                    throw Self.systemFailure("read frame")
                }
                if amount == 0 { reachedEOF = true; break }
                received += amount
            }
        }
        if reachedEOF {
            if allowEOF && received == 0 { return nil }
            throw SocketClientFailure.socket("The Silo socket closed inside a frame.")
        }
        return data
    }

    private static func systemFailure(_ operation: String) -> SocketClientFailure {
        .socket("\(operation): \(String(cString: strerror(errno)))")
    }
}

private struct SocketRequestFrame<Params: Encodable & Sendable>: Encodable {
    let id: String
    let method: String
    let params: Params
}

private struct SocketResponseFrame: Decodable {
    let id: String
    let result: SiloJSONValue?
    let error: SiloWireErrorObject?

    private enum CodingKeys: String, CodingKey { case id, result, error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        error = try container.decodeIfPresent(SiloWireErrorObject.self, forKey: .error)
        result = container.contains(.result) ? try container.decode(SiloJSONValue.self, forKey: .result) : nil
    }
}

private actor SocketRequestTransport {
    private let socket: UnixDomainSocket
    private var readerTask: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var closed = false
    private var eventHandler: (@Sendable (SiloWireEventEnvelope) -> Void)?
    private var disconnectHandler: (@Sendable (String) -> Void)?

    init(path: String) throws { socket = try UnixDomainSocket(path: path) }

    func setEventHandler(_ handler: @escaping @Sendable (SiloWireEventEnvelope) -> Void) {
        eventHandler = handler
    }

    func setDisconnectHandler(_ handler: @escaping @Sendable (String) -> Void) {
        disconnectHandler = handler
    }

    func start() {
        guard readerTask == nil else { return }
        let socket = self.socket
        readerTask = Task.detached(priority: .utility) { [weak self] in
            do {
                while !Task.isCancelled {
                    guard let frame = try socket.readFrame() else { throw SocketClientFailure.closed }
                    await self?.receive(frame)
                }
            } catch {
                await self?.connectionFailed(error)
            }
        }
    }

    func request<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        _ call: SiloGeneratedMethodCall<Params, Result>
    ) async throws -> Result {
        guard !closed else { throw SocketClientFailure.closed }
        let id = UUID().uuidString.lowercased()
        let request = try JSONEncoder().encode(SocketRequestFrame(id: id, method: call.name, params: call.params))
        let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pending[id] = continuation
            do {
                try socket.writeFrame(request)
            } catch {
                pending.removeValue(forKey: id)
                connectionFailed(error)
                continuation.resume(throwing: error)
            }
        }
        let response = try JSONDecoder().decode(SocketResponseFrame.self, from: responseData)
        guard response.id == id else { throw SocketClientFailure.malformed("response id did not match request") }
        guard !(response.error != nil && response.result != nil) else {
            throw SocketClientFailure.malformed("response included both result and error")
        }
        if let error = response.error { throw SocketClientFailure.remote(error.code.rawValue, error.message) }
        guard let result = response.result else { throw SocketClientFailure.malformed("response omitted result") }
        let resultData = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(Result.self, from: resultData)
    }

    func close() {
        guard !closed else { return }
        closed = true
        readerTask?.cancel()
        readerTask = nil
        socket.shutdown()
        failPending(SocketClientFailure.closed)
    }

    private func receive(_ frame: Data) {
        guard !closed else { return }
        do {
            let object = try JSONSerialization.jsonObject(with: frame) as? [String: Any]
            if object?["event"] != nil {
                let envelope = try JSONDecoder().decode(SiloWireEventEnvelope.self, from: frame)
                eventHandler?(envelope)
            } else {
                let response = try JSONDecoder().decode(SocketResponseFrame.self, from: frame)
                guard let continuation = pending.removeValue(forKey: response.id) else {
                    throw SocketClientFailure.malformed("response id did not match a pending request")
                }
                continuation.resume(returning: frame)
            }
        } catch {
            connectionFailed(error)
        }
    }

    private func connectionFailed(_ error: Error) {
        guard !closed else { return }
        closed = true
        socket.shutdown()
        failPending(error)
        disconnectHandler?(error.localizedDescription)
    }

    private func failPending(_ error: Error) {
        let continuations = Array(pending.values)
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }
}

/// A debug-selectable Unix-socket implementation. It performs `engine.handshake` before
/// issuing any other request and reconnects with fresh subscriptions after socket loss.
@MainActor
final class SocketEngineClient: EngineClient {
    static let defaultProtocolRange = SiloWireProtocolRange(min: 1, max: 1)
    static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".silo/engine.sock").path
    }

    private struct Subscription {
        let events: [String]
        let handler: @MainActor (EngineEventDelivery) -> Void
        var serverId: String?
        var sequence: UInt64?
    }

    private let path: String
    private let protocolRange: SiloWireProtocolRange
    private var transport: SocketRequestTransport?
    private var connectionTask: Task<SocketRequestTransport, Error>?
    private var reconnectTask: Task<Void, Never>?
    private var connectionGeneration: UInt64 = 0
    private var shouldResync = false
    private var explicitlyDisconnected = false
    private var subscriptions: [String: Subscription] = [:]
    private var subscriptionByServerId: [String: String] = [:]
    private var unmatchedEvents: [SiloWireEventEnvelope] = []
    private(set) var handshakeResult: SiloWireHandshakeResult?

    init(path: String = Self.defaultSocketPath, protocolRange: SiloWireProtocolRange = Self.defaultProtocolRange) {
        self.path = path
        self.protocolRange = protocolRange
    }

    func deviceFactsRead(deviceId: String?) async throws -> DeviceFacts {
        let wire = try await invoke(SiloGeneratedMethods.deviceFacts(SiloWireDeviceParams(deviceId: deviceId)))
        return DeviceFacts(
            deviceCapacity: wire.deviceCapacity.map {
                DeviceCapacity(logicalCpus: $0.logicalCpus, physicalMemoryBytes: $0.physicalMemoryBytes,
                               maxMemoryGib: Int(exactly: $0.maxMemoryGib) ?? Int.max)
            },
            macosHostLimits: wire.macosHostLimits.map {
                MacosHostLimits(cpus: Int(exactly: $0.cpus) ?? Int.max, memory_gib: Int(exactly: $0.memoryGib) ?? Int.max)
            },
            remoteLogin: wire.remoteLogin)
    }

    func computersList(deviceId: String?) async throws -> ComputerInventory {
        try await invoke(SiloGeneratedMethods.computersList(SiloWireComputerListParams(deviceId: deviceId)))
    }

    func computersCreate(_ request: ComputerCreateRequest) async throws -> ComputerCreateResult {
        let wireRequest: SiloWireMacosComputerCreateRequest?
        if let value = request.request {
            guard let cpus = UInt64(exactly: value.cpus), let memory = UInt64(exactly: value.memoryGiB),
                  let disk = UInt64(exactly: value.diskGiB) else {
                throw EngineClientError.invalidAction("macOS computer limits must be nonnegative integers.")
            }
            wireRequest = SiloWireMacosComputerCreateRequest(cpus: cpus, diskGiB: disk, memoryGiB: memory, name: value.name)
        } else {
            wireRequest = nil
        }
        let params = SiloWireComputerCreateParams(configuration: request.configuration, deviceId: request.deviceId,
                                                   kind: request.kind, requestId: request.requestId, request: wireRequest)
        return try await invoke(SiloGeneratedMethods.computersCreate(params))
    }

    func computersStart(_ reference: ComputerReference) async throws -> ComputerJob {
        try await invoke(SiloGeneratedMethods.computersStart(reference))
    }

    func computersStop(_ reference: ComputerReference) async throws -> ComputerJob {
        try await invoke(SiloGeneratedMethods.computersStop(reference))
    }

    func computersForceStop(_ reference: ComputerReference) async throws {
        let _: SiloNull = try await invoke(SiloGeneratedMethods.computersForceStop(reference))
    }

    func computersDelete(_ request: ComputerDeleteRequest) async throws -> ComputerJob {
        try await invoke(SiloGeneratedMethods.computersDelete(request))
    }

    func computersConfigurationRead(deviceId: String?) async throws -> ComputerConfigurationRequest {
        try await invoke(SiloGeneratedMethods.computersConfigurationRead(SiloWireDeviceParams(deviceId: deviceId)))
    }

    func checkpointsList(computerId: String, deviceId: String?) async throws -> [ComputerCheckpoint] {
        let inventory = try await computersList(deviceId: deviceId)
        guard let row = inventory.computer(computerId) else { throw EngineClientError.notFound("This computer no longer exists.") }
        return row.checkpoints
    }

    func checkpointsCreate(_ request: CheckpointCreateRequest) async throws -> ComputerJob {
        try await invoke(SiloGeneratedMethods.checkpointsCreate(request))
    }

    func checkpointsRestore(_ request: CheckpointRestoreRequest) async throws -> ComputerJob {
        try await invoke(SiloGeneratedMethods.checkpointsRestore(request))
    }

    func checkpointsFork(_ request: CheckpointForkRequest) async throws -> ComputerJob {
        try await invoke(SiloGeneratedMethods.checkpointsFork(request))
    }

    func checkpointsDelete(_ request: CheckpointDeleteRequest) async throws -> ComputerJob {
        try await invoke(SiloGeneratedMethods.checkpointsDelete(request))
    }

    func displayShow(_ reference: ComputerReference) async throws {
        let _: SiloNull = try await invoke(SiloGeneratedMethods.displayShow(reference))
    }

    func operationsList(deviceId: String?) async throws -> OperationsList {
        let queue = try await invoke(SiloGeneratedMethods.operationsList(SiloWireOperationsListParams(deviceId: deviceId)))
        return OperationsList(running: queue.running.map(Self.projectQueueEntry),
                              waiting: queue.waiting.map(Self.projectQueueEntry),
                              unacknowledgedJobIds: queue.unacknowledgedJobIds)
    }

    func operationsJobGet(jobId: String, deviceId: String?) async throws -> OperationJobSnapshot {
        let result = try await invoke(SiloGeneratedMethods.operationsJobGet(SiloWireGetJobParams(deviceId: deviceId, jobId: jobId)))
        return OperationJobSnapshot(jobId: result.jobId, state: OperationJobState(rawValue: result.state.rawValue) ?? .running,
                                     outcome: result.outcome.map {
                                         OperationJobOutcome(result: $0.result, error: $0.error.map(Self.projectError))
                                     })
    }

    func operationsCancel(jobId: String, deviceId: String?) async throws {
        let _: SiloNull = try await invoke(SiloGeneratedMethods.operationsCancel(SiloWireCancelJobParams(deviceId: deviceId, jobId: jobId)))
    }

    func eventsSubscribe(events: [String], handler: @escaping @MainActor (EngineEventDelivery) -> Void) async throws -> String {
        let result = try await invoke(SiloGeneratedMethods.eventsSubscribe(SiloWireEventsSubscribeParams(events: events)))
        let localId = UUID().uuidString.lowercased()
        subscriptions[localId] = Subscription(events: events, handler: handler, serverId: result.subscription, sequence: nil)
        subscriptionByServerId[result.subscription] = localId
        drainUnmatchedEvents(for: result.subscription)
        return localId
    }

    func eventsUnsubscribe(subscription: String) async {
        guard let entry = subscriptions.removeValue(forKey: subscription) else { return }
        if let serverId = entry.serverId {
            subscriptionByServerId.removeValue(forKey: serverId)
            guard let transport else { return }
            let params = SiloWireEventsUnsubscribeParams(subscription: serverId)
            let call = SiloGeneratedMethods.eventsUnsubscribe(params)
            do { let _: SiloNull = try await transport.request(call) } catch { }
        }
    }

    func operationsJobAcknowledge(jobId: String, deviceId: String?) async throws {
        let params = SiloWireAcknowledgeJobParams(deviceId: deviceId, jobId: jobId)
        let _: SiloNull = try await invoke(SiloGeneratedMethods.operationsJobAcknowledge(params))
    }

    func engineDisconnect() async throws {
        explicitlyDisconnected = true
        reconnectTask?.cancel()
        reconnectTask = nil
        guard let transport else { return }
        do {
            let _: SiloNull = try await transport.request(SiloGeneratedMethods.engineDisconnect([:]))
            await transport.close()
            self.transport = nil
        } catch {
            await transport.close()
            self.transport = nil
            throw Self.map(error)
        }
    }

    private func invoke<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        _ call: SiloGeneratedMethodCall<Params, Result>
    ) async throws -> Result {
        do {
            let activeTransport = try await ensureTransport()
            return try await activeTransport.request(call)
        }
        catch { throw Self.map(error) }
    }

    private func ensureTransport() async throws -> SocketRequestTransport {
        guard !explicitlyDisconnected else { throw SocketClientFailure.closed }
        if let transport { return transport }
        if let connectionTask { return try await connectionTask.value }
        guard protocolRange.min <= protocolRange.max else {
            throw EngineClientError.invalidAction("The supported Silo protocol range is invalid.")
        }
        let task = Task { @MainActor in try await self.openTransport() }
        connectionTask = task
        do {
            let opened = try await task.value
            connectionTask = nil
            return opened
        } catch {
            connectionTask = nil
            throw Self.map(error)
        }
    }

    private func openTransport() async throws -> SocketRequestTransport {
        let candidate = try SocketRequestTransport(path: path)
        connectionGeneration &+= 1
        let generation = connectionGeneration
        await candidate.setEventHandler { [weak self] envelope in
            Task { @MainActor [weak self] in self?.receive(envelope) }
        }
        await candidate.setDisconnectHandler { [weak self] reason in
            Task { @MainActor [weak self] in self?.connectionLost(reason, generation: generation) }
        }
        await candidate.start()
        do {
            let params = SiloWireHandshakeParams(
                client: SiloWireClientMetadata(name: "Fjord", version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"),
                handshakeParamsProtocol: protocolRange)
            let result = try await candidate.request(SiloGeneratedMethods.engineHandshake(params))
            guard (protocolRange.min...protocolRange.max).contains(result.handshakeResultProtocol) else {
                throw SocketClientFailure.incompatibleVersion(result.handshakeResultProtocol, protocolRange)
            }
            handshakeResult = result
            transport = candidate
            if shouldResync { try await restoreSubscriptions(on: candidate) }
            return candidate
        } catch {
            await candidate.close()
            throw Self.map(error)
        }
    }

    private func restoreSubscriptions(on candidate: SocketRequestTransport) async throws {
        subscriptionByServerId.removeAll()
        for localId in subscriptions.keys.sorted() {
            guard var subscription = subscriptions[localId] else { continue }
            let params = SiloWireEventsSubscribeParams(events: subscription.events)
            let response = try await candidate.request(SiloGeneratedMethods.eventsSubscribe(params))
            subscription.serverId = response.subscription
            subscription.sequence = nil
            subscriptions[localId] = subscription
            subscriptionByServerId[response.subscription] = localId
        }
        if shouldResync {
            shouldResync = false
            for subscription in subscriptions.values { subscription.handler(.reconnected) }
        }
        let serverIds = Set(subscriptionByServerId.keys)
        for id in serverIds { drainUnmatchedEvents(for: id) }
    }

    private func connectionLost(_ reason: String, generation: UInt64) {
        guard generation == connectionGeneration, !explicitlyDisconnected else { return }
        transport = nil
        subscriptionByServerId.removeAll()
        unmatchedEvents.removeAll()
        shouldResync = true
        for id in Array(subscriptions.keys) {
            guard var subscription = subscriptions[id] else { continue }
            subscription.serverId = nil
            subscription.sequence = nil
            subscriptions[id] = subscription
            subscription.handler(.disconnected(reason))
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil, !explicitlyDisconnected else { return }
        reconnectTask = Task { @MainActor [weak self] in
            var delay: Int64 = 200
            while let self, !Task.isCancelled, !self.explicitlyDisconnected {
                do {
                    try await Task.sleep(for: .milliseconds(delay))
                    _ = try await self.ensureTransport()
                    self.reconnectTask = nil
                    return
                } catch {
                    delay = min(delay * 2, 5_000)
                }
            }
            self?.reconnectTask = nil
        }
    }

    private func receive(_ envelope: SiloWireEventEnvelope) {
        guard let localId = subscriptionByServerId[envelope.subscription] else {
            unmatchedEvents.append(envelope)
            if unmatchedEvents.count > 128 { unmatchedEvents.removeFirst(unmatchedEvents.count - 128) }
            return
        }
        deliver(envelope, to: localId)
    }

    private func drainUnmatchedEvents(for serverId: String) {
        let events = unmatchedEvents.filter { $0.subscription == serverId }
        unmatchedEvents.removeAll { $0.subscription == serverId }
        for event in events {
            if let localId = subscriptionByServerId[serverId] { deliver(event, to: localId) }
        }
    }

    private func deliver(_ envelope: SiloWireEventEnvelope, to localId: String) {
        guard var subscription = subscriptions[localId] else { return }
        if let previous = subscription.sequence {
            guard envelope.seq > previous else { return }
            if envelope.seq != previous &+ 1 {
                subscription.sequence = envelope.seq
                subscriptions[localId] = subscription
                subscription.handler(.reconnected)
                return
            }
        }
        subscription.sequence = envelope.seq
        subscriptions[localId] = subscription
        guard let event = Self.projectEvent(envelope) else { return }
        subscription.handler(.event(sequence: envelope.seq, event: event))
    }

    private static func projectEvent(_ envelope: SiloWireEventEnvelope) -> EngineEvent? {
        guard let payload = envelope.payload, let data = try? JSONEncoder().encode(payload) else { return nil }
        let decoder = JSONDecoder()
        switch envelope.event {
        case .computersChanged:
            guard let value = try? decoder.decode(ComputersChangedPayload.self, from: data) else { return nil }
            return .computersChanged(value)
        case .checkpointsChanged:
            guard let value = try? decoder.decode(CheckpointsChangedPayload.self, from: data) else { return nil }
            return .checkpointsChanged(value)
        case .operationsQueueChanged:
            guard let value = try? decoder.decode(SiloWireOperationQueue.self, from: data) else { return nil }
            return .operationsQueueChanged(OperationsList(
                running: value.running.map(projectQueueEntry), waiting: value.waiting.map(projectQueueEntry),
                unacknowledgedJobIds: value.unacknowledgedJobIds))
        case .operationsJobProgress:
            guard let value = try? decoder.decode(SiloWireJobProgress.self, from: data),
                  let progress = try? projectProgress(value) else { return nil }
            return .jobProgress(progress)
        case .operationsJobFinished:
            guard let value = try? decoder.decode(SiloWireJobFinished.self, from: data) else { return nil }
            return .jobFinished(OperationJobFinished(jobId: value.jobId, result: value.result,
                                                      error: value.error.map(projectError)))
        default:
            return nil
        }
    }

    private static func projectProgress(_ wire: SiloWireJobProgress) throws -> OperationJobProgress {
        let source = JobProgressSource(rawValue: wire.source.rawValue) ?? .macos
        let data = wire.data
        let projection: OperationJobProgressData
        switch source {
        case .setup:
            let fraction = data.fraction.map { value in value > 1 ? Double(value) / 100 : Double(value) }
            projection = .setup(SetupJobProgressData(
                schemaVersion: data.schemaVersion ?? 1, type: data.type ?? "computer-configuration",
                requestId: data.requestId ?? wire.jobId, phase: data.phase ?? "", step: data.step ?? "",
                computer: data.computer, fraction: fraction, message: data.message ?? "",
                safeForDisplay: data.safeForDisplay ?? true, timestamp: String(data.timestamp ?? 0),
                level: data.level ?? "info", elapsedSeconds: Double(data.elapsedSeconds ?? 0),
                downloadedBytes: data.downloadedBytes, totalBytes: data.totalBytes,
                failureCode: data.failureCode, exitCode: data.exitCode.map { Int($0) },
                diagnostic: data.diagnostic, partial: data.partial ?? false))
        case .lifecycle:
            projection = .lifecycle(LifecycleJobProgressData(computerId: data.computerId ?? wire.computerId ?? "",
                                                              action: data.action ?? "", step: data.step ?? ""))
        case .transfer:
            projection = .transfer(TransferJobProgressData(
                id: data.id ?? wire.jobId, computer: data.computer ?? wire.computerId ?? "",
                direction: data.direction?.rawValue ?? "download", state: data.state?.rawValue ?? "transferring",
                name: data.name ?? "", fileIndex: UInt64(max(0, data.fileIndex ?? 0)),
                fileCount: UInt64(max(0, data.fileCount ?? 0)), bytesDone: data.bytesDone ?? 0,
                bytesTotal: data.bytesTotal ?? 0))
        case .backup:
            let archive = data.archive
            let phase = data.phases?.map { BackupJobProgressPhase(title: $0.title, detail: $0.detail, tone: $0.tone) } ?? []
            projection = .backup(BackupJobProgressData(
                operation: data.operation?.rawValue ?? wire.jobId,
                archive: BackupJobProgressArchive(name: archive?.name ?? "backup", archivePath: archive?.archivePath ?? "",
                                                  completedLabel: archive?.completedLabel ?? "Backup",
                                                  size: UInt64(archive?.size ?? "") ?? 0,
                                                  destination: archive?.destination ?? "", computers: archive?.computers ?? [],
                                                  checkpointName: archive?.checkpointName),
                runningNames: data.runningNames ?? [], targetName: data.targetName,
                progress: UInt8(max(0, min(100, numericProgress(data.progress) ?? 0))),
                indeterminate: data.indeterminate, canCancel: data.canCancel, phases: phase))
        case .push:
            let target = data.target.flatMap(encodeJSONValue) ?? .null
            projection = .push(PushJobProgressData(
                operationId: data.operationId ?? wire.jobId, computer: data.computer ?? wire.computerId ?? "",
                repositoryPath: data.repositoryPath ?? "", status: data.status?.rawValue ?? "unknown",
                commitCount: Int(exactly: data.commitCount ?? 0) ?? Int.max, message: data.message, target: target))
        case .macos:
            projection = .macos(MacosJobProgressData(computerId: data.computerId ?? wire.computerId ?? "",
                                                      state: data.state?.rawValue ?? "running",
                                                      progress: numericProgress(data.progress), detail: data.detail,
                                                      checkpointOperation: data.checkpointOperation))
        case .update:
            projection = .update(UpdateJobProgressData(
                phase: data.phase ?? "", lastChecked: data.lastChecked, retryAction: data.retryAction,
                currentVersion: data.currentVersion ?? "", availableVersion: data.availableVersion,
                releaseNotes: data.releaseNotes, downloadedBytes: data.downloadedBytes, totalBytes: data.totalBytes,
                automaticChecks: data.automaticChecks ?? false, packageKind: data.packageKind ?? "",
                releaseUrl: data.releaseUrl ?? "", error: data.error, errorDetails: data.errorDetails,
                runningComputers: data.runningComputers ?? [], canInstall: data.canInstall ?? false,
                installBlockReason: data.installBlockReason))
        }
        return OperationJobProgress(jobId: wire.jobId, kind: wire.kind?.rawValue, computerId: wire.computerId,
                                    source: source, data: projection)
    }

    private static func numericProgress(_ value: SiloWireProgress?) -> Double? {
        switch value {
        case .double(let value): value
        case .integer(let value): Double(value)
        case .null, nil: nil
        }
    }

    private static func encodeJSONValue<Value: Encodable>(_ value: Value) -> SiloJSONValue? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(SiloJSONValue.self, from: data)
    }

    private static func projectQueueEntry(_ value: SiloWireOperationEntry) -> OperationQueueEntry {
        OperationQueueEntry(id: value.id, jobId: value.jobId, label: value.label, kind: value.kind.rawValue,
                            computerId: value.computerId, computerName: value.computerName, sinceMs: value.sinceMs,
                            cancellable: value.cancellable, expectedMs: value.expectedMs,
                            blockedByHidden: value.blockedByHidden ?? false)
    }

    private static func projectError(_ value: SiloWireErrorObject) -> OperationJobError {
        OperationJobError(code: value.code.rawValue, message: value.message)
    }

    private static func map(_ error: Error) -> Error {
        (error as? SocketClientFailure)?.engineError ?? error
    }
}
