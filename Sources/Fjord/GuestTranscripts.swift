import Foundation

/// A bounded, authoritative view of one guest transcript. The local `ssh-<id>` mirror is never consulted for this data.
struct GuestTranscriptSnapshot: Equatable, Sendable {
    var computer: GuestReference
    var cliSessionID: String
    var path: String
    var inode: Int64
    var size: Int64
    var mtimeMs: Int64
    var tail: Data

    var messages: [SessionFork.Message] { SessionFork.messages(in: tail) }
    var activity: ClaudeActivity? { Claude.activity(tail: tail) }
    var finalMessage: String? { Claude.finalMessage(tail: tail) }
    var recentSteps: [Claude.TranscriptStep] { Claude.recentTimedSteps(tail: tail) }
    var earlierTurnEnds: [String] { Array(Claude.turnEnds(tail: tail).dropLast()) }
}

/// Reads guest transcript files by path and metadata through guest.files. No guest path is normalized by the host.
struct GuestTranscripts: Sendable {
    var client: any GuestClient
    var tailLimit = 1 << 20
    var projectLimit = 512

    func read(computer: GuestReference, projectsRoot: String, cliSessionID: String) async throws -> GuestTranscriptSnapshot? {
        let projects: [GuestFileEntry]
        do { projects = try await client.filesList(computer: computer, path: projectsRoot) }
        catch GuestClientFailure.notFound(_) { return nil }

        var matches: [(String, GuestFileEntry)] = []
        for project in projects.prefix(projectLimit) where project.type == .directory {
            let directory = GuestRouterPaths.join(projectsRoot, project.name)
            let entries: [GuestFileEntry]
            do { entries = try await client.filesList(computer: computer, path: directory) }
            catch GuestClientFailure.notFound(_) { continue }
            if let file = entries.first(where: { $0.type == .file && $0.name == "\(cliSessionID).jsonl" }) {
                matches.append((directory, file))
            }
        }
        // The CLI id is expected to name one project transcript. Ambiguity is not a reason to read an arbitrary copy.
        guard matches.count == 1, let (directory, entry) = matches.first else { return nil }
        let offset = max(0, entry.size - Int64(max(0, tailLimit)))
        let length = Int(min(Int64(max(0, tailLimit)), entry.size))
        let path = GuestRouterPaths.join(directory, entry.name)
        let read = try await client.filesRead(computer: computer, path: path, offset: offset, length: length)
        guard read.size == entry.size, offset + Int64(read.data.count) == read.size else { return nil }
        let complete = Self.completeLines(read.data, startsAtFileBeginning: offset == 0)
        return GuestTranscriptSnapshot(computer: computer, cliSessionID: cliSessionID, path: path,
            inode: read.inode, size: read.size, mtimeMs: read.mtimeMs, tail: complete)
    }

    /// Drops the leading partial line after a ranged read and the trailing line while a writer may still be appending it.
    static func completeLines(_ data: Data, startsAtFileBeginning: Bool) -> Data {
        var lower = data.startIndex
        if !startsAtFileBeginning {
            guard let firstNewline = data.firstIndex(of: 0x0a) else { return Data() }
            lower = data.index(after: firstNewline)
        }
        guard lower < data.endIndex, let lastNewline = data.lastIndex(of: 0x0a), lastNewline >= lower else { return Data() }
        return Data(data[lower...lastNewline])
    }
}
