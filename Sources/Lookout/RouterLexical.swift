import Foundation

// What the words say, beside Jev: BM25 between your message and each session's recent turns, by field (its last
// answer, what you last told it, its older turns halving with age, its title). On real moments of your own sessions it
// names where a message went more often than Jev does (54% vs 40–48%; evals/router/explore/lexical.py), and the fusion
// weighs it (RouteFusion). Read from the session's transcript; from what the board shows when there is none.

enum RouterLexical {
    /// One exchange: what you said, and the session's last answer to it ("" while it is still working on it).
    struct Turn: Equatable {
        var you: String
        var said: String
    }

    struct Field {
        /// How many of the latest turns (0: all of them).
        var turns: Int
        var you: Double = 1
        var said: Double = 1
        var title: Double = 0
        /// Each older turn counts this much of the next one.
        var decay: Double = 1
        /// Without the latest turn.
        var skipLatest = false
    }

    static let fields: [(name: String, field: Field)] = [
        ("f_said", Field(turns: 1, you: 0)),
        ("f_you", Field(turns: 1, said: 0)),
        ("f_old", Field(turns: 0, decay: 0.5, skipLatest: true)),
        ("f_title", Field(turns: 1, you: 0, said: 0, title: 1)),
    ]
    static let k1 = 1.2
    static let b = 0.3

    // MARK: Words

    static let stop: Set<String> = Set(("the and for with this that these those from into onto you your please can could would should will what when " +
        "where which who why how about then than them they have has had not are was were its our out all any some just " +
        "also now new session project card does did but yes too there here let one get make use need want like ok okay thanks " +
        "what when where which while will with would this those was were you your yes why who very want use using used way well " +
        "too only more most much same other each both after before again still even being been because doing done don doesn " +
        "didn isn it's i'm they their think know see look go going sure right good work works thing things " +
        "les des une est pas que qui pour dans sur avec mais fait faire tout plus bien aussi comme cette ces son ses elle nous " +
        "vous ils leur sont ont été etre être par donc alors oui non quoi").split(separator: " ").map(String.init))

    /// Lowercased, accents off, runs of letters and digits of 3 or more, without common words and short numbers, their
    /// plural and verb endings cut.
    static func tokens(_ text: String) -> [String] {
        let folded = text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { $0.properties.generalCategory != .nonspacingMark }
        var out: [String] = [], word = String.UnicodeScalarView()
        func flush() {
            let w = String(word)
            word = String.UnicodeScalarView()
            guard w.count >= 3, !stop.contains(w), !(w.allSatisfy(\.isNumber) && w.count < 4) else { return }
            out.append(stem(w))
        }
        for scalar in folded {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar.properties.generalCategory == .decimalNumber {
                word.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    static func stem(_ w: String) -> String {
        for suffix in ["ations", "ation", "ings", "ing", "edly", "ies", "ied", "ers", "er", "ed", "ly", "es", "s"]
        where w.hasSuffix(suffix) && w.count - suffix.count >= 4 {
            var cut = String(w.dropLast(suffix.count))
            if suffix == "ies" || suffix == "ied" { cut += "y" }
            return cut
        }
        return w
    }

    // MARK: Scores

    /// A field's weighted word counts. A part the field leaves out (weight 0) still lists its words, at 0: they count
    /// as the session's for IDF, not for the score (as measured in evals/router/explore/lexical.py).
    static func termCounts(title: String, turns: [Turn], _ f: Field) -> [String: Double] {
        var tf: [String: Double] = [:]
        for w in tokens(title) { tf[w, default: 0] += f.title }
        var kept = f.skipLatest ? Array(turns.dropLast()) : turns
        if f.turns > 0 { kept = Array(kept.suffix(f.turns)) }
        for (i, turn) in kept.enumerated() {
            let weight = pow(f.decay, Double(kept.count - 1 - i))
            for w in tokens(turn.you) { tf[w, default: 0] += weight * f.you }
            for w in tokens(turn.said) { tf[w, default: 0] += weight * f.said }
        }
        return tf
    }

    /// Per session, BM25 of `message` against it in field `f`, divided by the best session's (IDF over these sessions).
    static func scores(_ message: String, sessions: [String: (title: String, turns: [Turn])], _ f: Field) -> [String: Double] {
        let query = Set(tokens(message))
        guard !query.isEmpty, !sessions.isEmpty else { return sessions.mapValues { _ in 0 } }
        let docs = sessions.mapValues { termCounts(title: $0.title, turns: $0.turns, f) }
        let lengths = docs.mapValues { $0.values.reduce(0, +) }
        let total = lengths.values.reduce(0, +) / Double(docs.count)
        let average = total == 0 ? 1 : total
        let n = Double(docs.count)
        var df: [String: Double] = [:]
        for tf in docs.values { for w in tf.keys where query.contains(w) { df[w, default: 0] += 1 } }
        var out: [String: Double] = [:]
        for (id, tf) in docs {
            var score = 0.0
            for w in query {
                guard let count = tf[w], count > 0 else { continue }
                let d = df[w] ?? 0
                let idf = log(1 + (n - d + 0.5) / (d + 0.5))
                score += idf * count * (k1 + 1) / (count + k1 * (1 - b + b * (lengths[id] ?? 0) / average))
            }
            out[id] = score
        }
        let best = out.values.max() ?? 0
        return out.mapValues { best > 0 ? $0 / best : 0 }
    }

    /// Every field's scores: field name → session → score.
    static func all(_ message: String, sessions: [String: (title: String, turns: [Turn])]) -> [String: [String: Double]] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.name, scores(message, sessions: sessions, $0.field)) })
    }

    // MARK: Turns

    private static let notTyped = try! NSRegularExpression(
        pattern: #"^\s*(<(command-|local-command|system-reminder|bash-|task-notification|user-prompt-submit)|Caveat:|\[Request interrupted)"#)

    /// The turns of a transcript's tail, oldest first: each message you typed and the session's last answer to it. The
    /// latest has no answer while `working`.
    static func turns(tail: Data, working: Bool) -> [Turn] {
        var out: [Turn] = []
        for line in tail.split(separator: UInt8(ascii: "\n")) {
            guard let record = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  record["isSidechain"] as? Bool != true else { continue }
            let content = (record["message"] as? [String: Any])?["content"]
            switch record["type"] as? String {
            case "user":
                guard record["isMeta"] as? Bool != true else { continue }
                var text: String
                if let s = content as? String {
                    text = s
                } else if let blocks = content as? [[String: Any]] {
                    if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { continue }
                    text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
                } else { continue }
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty,
                      notTyped.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil else { continue }
                out.append(Turn(you: text, said: ""))
            case "assistant":
                guard !out.isEmpty, let blocks = content as? [[String: Any]] else { continue }
                let said = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
                    .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !said.isEmpty { out[out.count - 1].said = said }
            default:
                continue
            }
        }
        if working, !out.isEmpty { out[out.count - 1].said = "" }
        return out
    }

    /// What the board shows about a session, laid out as its last turns: what you told it before with what it said
    /// earlier (its summary, its working line), then what you last told it with its cards.
    static func boardTurns(told: [String], cards: [String], earlier: [String]) -> [Turn] {
        [Turn(you: told.dropLast().joined(separator: " "), said: earlier.filter { !$0.isEmpty }.joined(separator: " ")),
         Turn(you: told.last ?? "", said: cards.joined(separator: " "))]
    }

    // MARK: What a session's last message leaves to you

    private static let asks = try! NSRegularExpression(pattern:
        #"\?\s*(\*\*)?\s*$|\b(want me to|should i|shall i|do you want|which one|would you like|let me know|tell me|say \*{0,2}"?\w+|your call|up to you|confirm|approve|if you agree)\b"#,
        options: [.caseInsensitive])
    private static let proposes = try! NSRegularExpression(pattern:
        #"\b(want me to|shall i|should i|i can|i could|i'?ll|i will|i'?d|next step|next,|then i|if you want|if you'?d like|if you confirm|unless you|ready to|once you)\b"#,
        options: [.caseInsensitive])

    /// The session's last message asks you something or proposes a next step: what "go", "yes" or "do it" answer.
    static func leavesItToYou(_ text: String, waiting: Bool) -> Bool {
        if waiting { return true }
        let range = NSRange(text.startIndex..., in: text)
        return asks.firstMatch(in: text, range: range) != nil || proposes.firstMatch(in: text, range: range) != nil
    }
}
