import Foundation

// The model and effort a session may start with (an inbox action's, or asked for in words: "…with opus, high effort"), and
// how a started session is marked. The model and effort ride inside the signed first message and the session's plugin sets
// them for that session (a plugin too old to is sent none, and the log says so).

// MARK: - Settings an action may carry

enum ActionSettings {
    /// What the editor offers as a model.
    static let models = ["opus", "sonnet", "haiku"]
    /// What the editor offers as an effort.
    static let efforts = ["low", "medium", "high", "max"]
    /// What a session's plugin is asked to set with `/model` and `/effort`: the aliases (with the 1M suffix) or a full id, and
    /// the five efforts.
    static let acceptedModels = ["opus", "sonnet", "haiku", "fable"]
    static let acceptedEfforts = ["low", "medium", "high", "xhigh", "max"]

    /// `value` as `/model` takes it: an alias, with or without `[1m]`, or a full `claude-…` id.
    static func cleanModel(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty, value.count <= 64 else { return nil }
        let base = value.hasSuffix("[1m]") ? String(value.dropLast(4)) : value
        if acceptedModels.contains(base) { return value }
        let id = base.dropFirst("claude-".count)
        guard base.hasPrefix("claude-"), !id.isEmpty, id.first?.isLetter == true || id.first?.isNumber == true,
              id.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "." || $0 == "-") }) else { return nil }
        return value
    }

    /// `value` if it is one of `allowed`; anything else (nothing, a value saved by a newer version) is the default.
    static func clean(_ value: String?, in allowed: [String]) -> String? {
        guard let value, allowed.contains(value) else { return nil }
        return value
    }
}

// MARK: - Sessions Fjord started

extension Store {
    /// Marks a session as started by Fjord: its cards are never held for the app showing it (see
    /// `RouterState.fjordStarted`).
    func noteFjordStarted(_ session: String, at date: Date = Date()) {
        guard router.fjordStarted[session] == nil else { return }
        router.fjordStarted[session] = date
    }

    /// Tags a session with what started it; its cards (open or not yet made) say so.
    func noteOrigin(_ origin: SessionOrigin, for session: String) {
        var state = router
        state.origins[session] = origin
        for i in state.cards.indices where state.cards[i].sessionID == session && state.cards[i].origin == nil {
            state.cards[i].origin = origin
        }
        router = state
    }
}

// MARK: - Model and effort for a session

/// The model and effort a new session should run with (nil: your Claude Code defaults). Values are allowlisted
/// (`ActionSettings`) before they go anywhere; they travel inside the signed message (`RelaySigner`) and the session's
/// plugin sets them for that session alone before its first prompt (`/model`, then `/effort`).
struct SessionSettings: Equatable, Sendable {
    var model: String?
    var effort: String?

    /// nil when neither value is one the plugin takes.
    init?(model: String?, effort: String?) {
        let model = ActionSettings.cleanModel(model), effort = ActionSettings.clean(effort, in: ActionSettings.acceptedEfforts)
        guard model != nil || effort != nil else { return nil }
        self.model = model
        self.effort = effort
    }

    /// The model and effort a request asks for (`SessionStart.settings(in:)`: before its task, or the clause it ends with),
    /// the first of each: "start a session with opus: …", "…fix the bug with opus, high effort", "don't use opus, use haiku"
    /// is haiku (`negated`). Nothing else in the text counts: "add a toggle for high effort" asks for nothing.
    static func parse(_ text: String) -> SessionSettings? {
        let asked = SessionStart.settings(in: text)
        func first(_ pattern: String) -> String? {
            for words in asked {
                if let r = words.range(of: pattern, options: [.regularExpression, .caseInsensitive]) { return words[r].lowercased() }
            }
            return nil
        }
        return SessionSettings(model: first(#"\b(?:opus|sonnet|haiku|fable)\b"#), effort: first(#"\b(?:low|medium|high|xhigh|max)\b"#))
    }

    /// A setting at `at` is said not to be wanted: a word of negation (`SessionStart.negations`) comes before it in its
    /// own clause, since a comma, a semicolon, a sentence's end, a line break or "but", "instead", "rather" ("don't use opus", "fix it
    /// without using opus").
    static func negated(_ text: String, before at: String.Index, from floor: String.Index? = nil) -> Bool {
        var start = text[..<at].lastIndex(where: { ",;.!?\n\r".contains($0) }).map(text.index(after:)) ?? text.startIndex
        if let floor, floor > start { start = floor }
        let keep = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'’"))
        let words = text[start..<at].lowercased().split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: keep).replacingOccurrences(of: "’", with: "'") }
        // "but", "instead" and "rather" begin a new, affirmative clause ("don't use opus but use haiku").
        let clause = words.lastIndex { ["but", "instead", "rather"].contains($0) }.map { words[($0 + 1)...] } ?? words[...]
        return clause.contains { SessionStart.negations.contains($0) }
    }
}

/// What the session's plugin did with a `SessionSettings`, from its ack, for the decision log.
struct AppliedSettings: Equatable, Sendable {
    var model: String?
    var effort: String?
    /// Why a setting did not apply, one per setting.
    var problems: [String] = []

    /// The plugin's ack ("ok model=opus effort=high", "ok model=error:why effort=high"), against what was asked. `nil` ack:
    /// delivered over the peer channel, which never applies settings. `supported` false: the plugin is too old to be sent them.
    static func from(ack: String?, requested: SessionSettings, supported: Bool) -> AppliedSettings {
        var out = AppliedSettings()
        guard supported else {
            out.problems = ["the session's plugin is older and can't set them"]
            return out
        }
        guard let ack else {
            out.problems = ["sent over the peer channel, which can't set them"]
            return out
        }
        var seen: Set<String> = []
        for token in ack.split(separator: " ").dropFirst() {
            guard let eq = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<eq]), value = String(token[token.index(after: eq)...])
            seen.insert(key)
            if value.hasPrefix("error:") {
                out.problems.append("\(key) not set: \(value.dropFirst("error:".count).replacingOccurrences(of: "_", with: " "))")
            } else if key == "model" {
                out.model = value
            } else if key == "effort" {
                out.effort = value
            }
        }
        for (key, asked) in [("model", requested.model), ("effort", requested.effort)] where asked != nil && !seen.contains(key) {
            out.problems.append("\(key) not reported by the plugin")
        }
        return out
    }

    /// Adds what was applied (and what wasn't) to a decision's log.
    func record(session: String?, project: String, in entry: inout RouterDecision) {
        entry.add(.started(session: session, project: project, model: model, effort: effort), session: session)
        for problem in problems { entry.add(.failed("model/effort: \(problem)")) }
    }
}
