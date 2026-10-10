import Foundation

// What a working session is doing, in a line, and what its turn did once it ends: composed from what Claude Code already
// writes (its task list, its own narration, the tool's description), with no model call.

enum RouterLive {
    /// The first sentence of some text, trimmed: plain, one line, short.
    static func firstSentences(_ text: String?, count: Int = 1, limit: Int = 200) -> String? {
        guard var text else { return nil }
        for mark in ["```", "**", "__", "`", "#"] { text = text.replacingOccurrences(of: mark, with: "") }
        // The first paragraph only: what follows is detail.
        let paragraph = text.components(separatedBy: "\n\n").first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? text
        text = paragraph.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        var seen = 0
        var end = text.endIndex
        var i = text.startIndex
        while i < text.endIndex {
            let next = text.index(after: i)
            if ".!?".contains(text[i]), next == text.endIndex || text[next] == " " {
                seen += 1
                if seen == count { end = next; break }
            }
            i = next
        }
        text = String(text[..<end])
        if text.count > limit { text = String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" }
        // A narration that trails off into a colon is not a sentence.
        if text.hasSuffix(":") { text.removeLast() }
        return text
    }

    private static let generic: Set<String> = ["Thinking", "Writing", "Working"]

    /// "3/7 · Running the test suite": the task list's progress, then its in-progress item, else the agent's own latest
    /// words, else the tool it is on.
    static func line(activity: ClaudeActivity?, tasks: [ClaudeTask] = []) -> String? {
        let progress = activity?.todo.flatMap { $0.total > 0 ? "\($0.done)/\($0.total)" : nil }
        let label = activity?.todo?.active.flatMap { firstSentences($0) }
            ?? firstSentences(activity?.narration)
            ?? activity.flatMap { generic.contains($0.text) ? nil : $0.text }
            ?? tasks.first.map { $0.title }
        switch (progress, label) {
        case let (p?, l?): return "\(p) · \(l)"
        case let (p?, nil): return p
        case let (nil, l?): return l
        default: return nil
        }
    }

    /// The hover text: the line, the goal (the session's title), the current step, and what the subagents are on.
    static func tooltip(title: String, activity: ClaudeActivity?, tasks: [ClaudeTask]) -> String {
        var lines = [line(activity: activity, tasks: tasks) ?? "Working", "Goal: \(title)"]
        if let step = activity?.text, !generic.contains(step) { lines.append("Now: \(step)") }
        let agents = tasks.filter { $0.kind == .agent }
        if !agents.isEmpty {
            lines.append(agents.count == 1 ? "1 subagent:" : "\(agents.count) subagents:")
            for agent in agents.prefix(6) {
                lines.append("• " + agent.title + (agent.activity.map { " (\($0.text))" } ?? ""))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// What the turn did: the app's own summary first, else the agent's final message, its first two sentences.
    static func turnSummary(session: ClaudeSession, activity: ClaudeActivity?) -> String? {
        if let detail = session.summary?.detail, !detail.isEmpty { return detail }
        guard !session.running else { return nil }
        return firstSentences(activity?.narration, count: 2, limit: 280)
    }
}

// MARK: - Store

extension Store {
    /// What the session's last turn did (the app's summary, else the agent's final words); nil while it runs or when there is
    /// neither. Later phases put it in the Router's context.
    func turnSummary(_ sessionID: String) -> String? {
        guard let session = claudeSessions[sessionID] else { return nil }
        return RouterLive.turnSummary(session: session, activity: claudeActivity[sessionID])
    }

    /// The live line of a working row.
    func liveExplanation(_ row: AgentRow) -> String? {
        row.session.running ? RouterLive.line(activity: row.activity, tasks: row.tasks) : RouterLive.line(activity: nil, tasks: row.tasks)
    }

    /// A finished turn's card that still has the placeholder takes the agent's final words when the app wrote no summary.
    func applyTurnSummaries(_ state: inout RouterState) {
        for i in state.cards.indices where state.cards[i].kind.isTurn && state.cards[i].text == RouterFeed.placeholder {
            let card = state.cards[i]
            guard let session = claudeSessions[card.sessionID], card.id == "\(card.sessionID)#t\(session.completedTurns)",
                  let text = turnSummary(card.sessionID) else { continue }
            state.cards[i].text = text
        }
    }
}
