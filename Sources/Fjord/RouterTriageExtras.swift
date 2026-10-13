import Foundation

// More of what Jev is asked about a finished turn, in the triage's one call (RouterTriage.swift): each extra brings its
// questions, what they read, and what it makes of the answers. Only input is billed, so a question more costs little.

struct TriageExtra {
    var questions: [String: JevClient.Question] = [:]
    var state: [String: String] = [:]
    var apply: ([String: JevClient.Answer], inout RouterTriage) -> Void = { _, _ in }
}

extension Store {
    /// The extras for this turn: only those whose cheap look says they may apply.
    func triageExtras(_ session: ClaudeSession, message: String, options: [RouterTriage.WaitOption]) async -> [TriageExtra] {
        var extras = [RouterAttention.trivialExtra, RouterTriage.nextExtra]
        if let circles = await circlesExtra(session, message: message) { extras.append(circles) }
        if let depends = dependsExtra(session, message: message, options: options) { extras.append(depends) }
        return extras
    }
}
