import Foundation

// A message you write in a session (in Claude, not through the Router) settles its open turn cards only as Jev judges it
// does (CardJudge, as for the Router's own sends): the feed notes the message (`RouterState.replies`), and its text, read
// from the transcript, is judged against the cards older than it. Unsure, failing or not asked, the cards stay open, until
// you mark them. Without Jev at all (no key, a demo), the message addresses them, as it used to.

extension Claude {
    /// Your latest reply in a transcript's tail: what you wrote since the session last spoke, oldest first, as one text
    /// (not a tool's result, a command or a system note); nil when there is none newer than `ms` (since 1970).
    static func userMessages(tail: Data, after ms: Int64) -> String? {
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        var texts: [String] = []
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = obj["type"] as? String, type == "user" || type == "assistant" else { continue }
            // The session spoke before it: your reply starts after that.
            if type == "assistant" { if texts.isEmpty { continue } else { break } }
            guard obj["isMeta"] as? Bool != true else { continue }
            let content = (obj["message"] as? [String: Any])?["content"]
            let text = (content as? String)
                ?? (content as? [[String: Any]])?.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, !text.hasPrefix("<") else { continue }
            if let at = (obj["timestamp"] as? String).flatMap({ try? Date($0, strategy: iso) }), RouterFeed.Stamp.ms(at) <= ms { break }
            texts.append(text)
        }
        let all = texts.reversed().joined(separator: "\n\n")
        return all.isEmpty ? nil : String(all.suffix(4000))
    }
}

extension Store {
    /// Judges each session's noted message against its open turn cards older than it, one at a time per session.
    func judgeReplies() {
        guard router.enabled else { return }
        for (sessionID, ms) in router.replies.sorted(by: { $0.key < $1.key }) where routerTriager.judgingReplies[sessionID] != ms {
            guard let session = claudeSessions[sessionID] else { continue }
            let cards = router.cards.filter { $0.sessionID == sessionID && $0.isOpen && $0.kind.isTurn && ms > $0.replyAfter }
            guard !cards.isEmpty else { settleReply(sessionID, ms); continue }
            let base = routerTriager.asker
            guard base != nil || !routerIsPretend, jevAsker(.cards, base: base) != nil else {
                // No Jev to ask: the message addresses them.
                var state = router
                RouterFeed.address(&state, sessionID, .reply, Date()) { card in cards.contains { $0.id == card.id } }
                state.replies[sessionID] = nil
                router = state
                continue
            }
            let eligible = Dictionary(cards.map { ($0.id, cardRevisions[$0.id, default: 0]) }, uniquingKeysWith: { a, _ in a })
            let after = cards.map(\.replyAfter).min() ?? ms
            routerTriager.judgingReplies[sessionID] = ms
            routerTriager.replyJudging[sessionID] = Task { [weak self] in
                guard let self else { return }
                if let message = await self.replyText(session, after: after) {
                    await self.judgeCards(session: sessionID, message: message, eligible: eligible, asker: base, by: .reply)
                }
                if self.routerTriager.judgingReplies[sessionID] == ms { self.routerTriager.judgingReplies[sessionID] = nil }
                self.settleReply(sessionID, ms)
            }
        }
    }

    /// The message has been judged (or there was nothing to judge): forgotten, unless a newer one came meanwhile.
    private func settleReply(_ sessionID: String, _ ms: Int64) {
        guard router.replies[sessionID] == ms else { return }
        var state = router
        state.replies[sessionID] = nil
        router = state
    }

    private func replyText(_ session: ClaudeSession, after ms: Int64) async -> String? {
        if let reader = routerTriager.replyReader { return await reader(session, ms) }
        let reader = activityReader
        let cli = session.cliID
        return await Task.detached(priority: .utility) {
            cli.flatMap { reader.transcript($0) }.flatMap { Claude.userMessages(tail: Claude.tail(of: $0, bytes: 256 * 1024), after: ms) }
        }.value
    }
}
