import Darwin
import Foundation

actor FakeSiloRequestLog {
    struct Request: Sendable {
        let id: String
        let method: String
        let jobId: String?
        let protocolMin: Int?
        let protocolMax: Int?
    }

    private(set) var requests: [Request] = []

    func append(_ request: Request) { requests.append(request) }
}

final class FakeSiloUnixServer: @unchecked Sendable {
    let path: String
    let requestLog = FakeSiloRequestLog()

    private let listener: Int32
    private let stopLock = NSLock()
    private var isStopped = false
    private var task: Task<Void, Never>?

    init() throws {
        path = "/tmp/fjord-silo-\(UUID().uuidString).sock"
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Self.failure("create listener") }
        listener = fd
        var address = sockaddr_un()
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd)
            throw NSError(domain: "FakeSiloUnixServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Socket path is too long."])
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        pathBytes.withUnsafeBytes { source in
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                destination.initializeMemory(as: UInt8.self, repeating: 0)
                destination.copyBytes(from: source)
            }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 1) == 0 else {
            let error = Self.failure("bind listener")
            Darwin.close(fd)
            throw error
        }
        task = Task.detached(priority: .utility) { [weak self] in await self?.serve() }
    }

    deinit {
        stop()
    }

    func stop() {
        stopLock.lock()
        guard !isStopped else { stopLock.unlock(); return }
        isStopped = true
        stopLock.unlock()
        task?.cancel()
        _ = Darwin.shutdown(listener, SHUT_RDWR)
        Darwin.close(listener)
        _ = Darwin.unlink(path)
    }

    private func serve() async {
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        defer { Darwin.close(client) }
        var noSigPipe: Int32 = 1
        _ = Darwin.setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        while !Task.isCancelled, let frame = try? Self.readFrame(client) {
            guard let request = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
                  let id = request["id"] as? String, let method = request["method"] as? String else { return }
            let params = request["params"] as? [String: Any] ?? [:]
            let version = params["protocol"] as? [String: Any]
            await requestLog.append(.init(id: id, method: method, jobId: params["jobId"] as? String,
                                          protocolMin: version?["min"] as? Int, protocolMax: version?["max"] as? Int))
            if method == "operations.job.get" {
                let nextFrame: Data
                do {
                    guard let frame = try Self.readFrame(client) else { return }
                    nextFrame = frame
                } catch { return }
                guard let nextRequest = try? JSONSerialization.jsonObject(with: nextFrame) as? [String: Any],
                      let nextId = nextRequest["id"] as? String,
                      let nextMethod = nextRequest["method"] as? String,
                      nextMethod == "operations.job.get" else { return }
                let nextParams = nextRequest["params"] as? [String: Any] ?? [:]
                await requestLog.append(.init(id: nextId, method: nextMethod, jobId: nextParams["jobId"] as? String,
                                              protocolMin: nil, protocolMax: nil))
                guard (try? Self.writeFrame(Self.jobResult(id: nextId, jobId: nextParams["jobId"] as? String ?? ""), to: client)) != nil,
                      (try? Self.writeFrame(Self.jobResult(id: id, jobId: params["jobId"] as? String ?? ""), to: client)) != nil else { return }
                continue
            }
            let result: Any
            switch method {
            case "engine.handshake":
                result = ["deviceId": "device-1", "name": "Fake Silo", "protocol": 1, "capabilities": ["computers.*", "operations.*"]]
            case "events.subscribe":
                result = ["subscription": "sub-1"]
            default:
                result = NSNull()
            }
            guard (try? Self.writeFrame(["id": id, "result": result], to: client)) != nil else { return }
            if method == "events.subscribe" {
                for event in Self.sampleEvents {
                    guard (try? Self.writeFrame(event, to: client)) != nil else { return }
                }
            }
            if method == "engine.disconnect" { return }
        }
    }

    private static let sampleEvents: [[String: Any]] = [
        ["event": "operations.job.progress", "subscription": "sub-1", "deviceId": "device-1", "seq": 1,
         "payload": ["jobId": "job:fake", "source": "lifecycle",
                     "data": ["computerId": "computer-1", "action": "start", "step": "boot"]]],
        ["event": "operations.job.finished", "subscription": "sub-1", "deviceId": "device-1", "seq": 2,
         "payload": ["jobId": "job:fake", "result": ["answer": 42]]],
        ["event": "computers.changed", "subscription": "sub-1", "deviceId": "device-1", "seq": 4,
         "payload": ["linux": ["activities": [], "computers": [], "github": NSNull(),
                                  "repositoryPushOperations": [], "secrets": []]]],
    ]

    private static func jobResult(id: String, jobId: String) -> [String: Any] {
        ["id": id, "result": ["jobId": jobId, "state": "finished", "outcome": ["result": ["answer": 42]]]]
    }

    private static func readFrame(_ fd: Int32) throws -> Data? {
        guard let header = try readExactly(4, from: fd, allowEOF: true) else { return nil }
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= 4 * 1024 * 1024 else { throw failure("invalid frame length") }
        return try readExactly(Int(length), from: fd, allowEOF: false)
    }

    private static func readExactly(_ length: Int, from fd: Int32, allowEOF: Bool) throws -> Data? {
        var data = Data(count: length)
        var received = 0
        var eof = false
        try data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            while received < length {
                let count = Darwin.recv(fd, base.advanced(by: received), length - received, 0)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw failure("read frame")
                }
                if count == 0 { eof = true; break }
                received += count
            }
        }
        if eof {
            if allowEOF && received == 0 { return nil }
            throw failure("truncated frame")
        }
        return data
    }

    private static func writeFrame(_ value: [String: Any], to fd: Int32) throws {
        let payload = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        let length = UInt32(payload.count)
        var frame = Data([
            UInt8((length >> 24) & 0xff), UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff), UInt8(length & 0xff),
        ])
        frame.append(payload)
        try frame.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.send(fd, base.advanced(by: offset), buffer.count - offset, 0)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw failure("write frame")
                }
                guard count > 0 else { throw failure("socket closed") }
                offset += count
            }
        }
    }

    private static func failure(_ operation: String) -> NSError {
        NSError(domain: "FakeSiloUnixServer", code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "\(operation): \(String(cString: strerror(errno)))"])
    }
}
