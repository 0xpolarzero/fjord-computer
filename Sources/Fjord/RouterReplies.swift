import Foundation

// A message you write in a session (in Claude, not through the Router) clears its open turn cards as the feed sees it
// (`RouterFeed.queueReply`), and is noted (`RouterState.replies`): its text, read from the transcript, then tells what
// the cards it cleared asked that it left untouched, and what an earlier message left (CardJudge, as for the Router's own
// sends). The transcript may not have the message yet when the app says it was sent: it is read again a few times.

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
    /// Reads each session's noted message for the questions it left (`checkSkipped`), one at a time per session.
    func judgeReplies() {
        guard router.enabled else { return }
        for (sessionID, ms) in router.replies.sorted(by: { $0.key < $1.key }) where routerTriager.judgingReplies[sessionID] != ms {
            guard let session = claudeSessions[sessionID] else { continue }
            // The turn cards it cleared (as it was seen), and the questions an earlier message left.
            let cleared = router.cards.filter { card in
                card.sessionID == sessionID && card.kind.isTurn && card.addressedBy == .reply && ms > card.replyAfter
                    && card.addressedAt.map { RouterFeed.Stamp.ms($0) >= ms } == true
            }
            let pending = RouterFeed.unanswered(router.cards, sessionID, turns: session.completedTurns)
            guard !cleared.isEmpty || pending != nil else { settleReply(sessionID, ms); continue }
            let after = cleared.map(\.replyAfter).min() ?? ms - 1
            let base = routerTriager.asker
            routerTriager.judgingReplies[sessionID] = ms
            routerTriager.replyJudging[sessionID] = Task { [weak self] in
                guard let self else { return }
                if let message = await self.replyText(session, after: after) {
                    var state = self.router
                    for card in cleared {
                        guard let i = state.cards.firstIndex(where: { $0.id == card.id }), state.cards[i].addressedBy == .reply else { continue }
                        state.cards[i].addressedNote = message
                    }
                    if state != self.router { self.router = state }
                    await self.checkSkipped(session: sessionID, message: message, cleared: cleared, pending: pending, asker: base)
                }
                if self.routerTriager.judgingReplies[sessionID] == ms { self.routerTriager.judgingReplies[sessionID] = nil }
                self.settleReply(sessionID, ms)
            }
        }
    }

    /// The message has been read (or there was nothing to read it for): forgotten, unless a newer one came meanwhile.
    private func settleReply(_ sessionID: String, _ ms: Int64) {
        guard router.replies[sessionID] == ms else { return }
        var state = router
        state.replies[sessionID] = nil
        router = state
    }

    /// How long to wait before each new read of a transcript that doesn't have the message yet.
    static let replyRereads: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)]

    private func replyText(_ session: ClaudeSession, after ms: Int64) async -> String? {
        for wait in [Duration.zero] + routerTriager.replyRereads {
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled else { return nil }
            if let text = await readReply(session, after: ms) { return text }
        }
        return nil
    }

    private func readReply(_ session: ClaudeSession, after ms: Int64) async -> String? {
        if let reader = routerTriager.replyReader { return await reader(session, ms) }
        let guestRuntime = GuestRouterRuntime.shared
        if guestRuntime.location(for: session.id) != nil {
            return guestRuntime.transcript(for: session.id).flatMap { Claude.userMessages(tail: $0.tail, after: ms) }
        }
        let reader = activityReader
        let cli = session.cliID
        return await Task.detached(priority: .utility) {
            cli.flatMap { reader.transcript($0) }.flatMap { Claude.userMessages(tail: Claude.tail(of: $0, bytes: 256 * 1024), after: ms) }
        }.value
    }
}
