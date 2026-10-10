import Foundation

/// TypeSafe's Jev (a "System One" model): given some state and a list of options, it picks one, with probabilities.
/// It doesn't write text, and only input is billed. https://docs.typesafe.ai/api
struct JevClient {
    let key: String
    var endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    var session = Network.session

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Choice {
        let choice: String
        let confidence: Double
        /// Every option's probability (they sum to 1).
        let probabilities: [String: Double]
    }

    /// One typed question. Several go in one call (`ask`), each answered under its own key; only the input is billed.
    enum Question {
        /// One of `options` (a description for those whose name isn't enough).
        case choice([String], hints: [String: String] = [:], instructions: String)
        /// Yes or no: the probability of yes. `yes` and `no` say what each means when the question alone doesn't.
        case noul(instructions: String, yes: String? = nil, no: String? = nil)
        /// A rating on 2 to 10 ordered levels, lowest first.
        case score(levels: [String], instructions: String)
    }

    enum Answer {
        case choice(Choice)
        /// The probability of yes.
        case noul(Double)
        /// The probability-weighted level, 0 for the first level to `levels.count - 1` for the last.
        case score(Double, confidence: Double)

        var choice: Choice? { if case .choice(let c) = self { c } else { nil } }
        var yes: Double? { if case .noul(let p) = self { p } else { nil } }
        var score: Double? { if case .score(let s, _) = self { s } else { nil } }
    }

    /// Asks every question about `state` in one call.
    func ask(_ questions: [String: Question], about state: Any) async throws -> [String: Answer] {
        var body: [String: Any] = [:]
        var keys: [String: [String: String]] = [:]
        for (id, question) in questions {
            switch question {
            case .choice(let options, let hints, let instructions):
                let map = Dictionary(uniqueKeysWithValues: options.map { (Self.key(for: $0), $0) })
                keys[id] = map
                body[id] = ["type": "choice", "instructions": instructions,
                            "criteria": map.mapValues { option -> Any in hints[option] ?? NSNull() }]
            case .noul(let instructions, let yes, let no):
                var criteria: [String: Any] = [:]
                if let yes { criteria["true"] = yes }
                if let no { criteria["false"] = no }
                body[id] = ["type": "noul", "instructions": instructions, "criteria": criteria.isEmpty ? NSNull() as Any : criteria as Any]
            case .score(let levels, let instructions):
                body[id] = ["type": "score", "instructions": instructions, "criteria": levels]
            }
        }
        let data = try await post(["model": "jev-latest", "state": state, "questions": body])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = json["answers"] as? [String: Any] else { throw Failure(message: "Unexpected answer from TypeSafe") }
        var out: [String: Answer] = [:]
        for (id, question) in questions {
            guard let answer = answers[id] as? [String: Any] else { throw Failure(message: "TypeSafe left `\(id)` unanswered") }
            switch question {
            case .choice:
                out[id] = .choice(try Self.choice(answer, keys: keys[id] ?? [:]))
            case .noul:
                guard let p = Self.unit(answer["noul"]) else { throw Failure(message: "TypeSafe's yes/no for `\(id)` is invalid") }
                out[id] = .noul(p)
            case .score(let levels, _):
                guard let n = answer["score"] as? NSNumber, n.doubleValue.isFinite else {
                    throw Failure(message: "TypeSafe's score for `\(id)` is invalid")
                }
                // The legend numbers the levels; bring the score to 0…count-1 whatever it starts from.
                let first = (answer["legend"] as? [String: Any])?.keys.compactMap { Double($0) }.min()
                let raw = n.doubleValue
                let value = raw - (first ?? (raw > Double(levels.count - 1) ? 1 : 0))
                out[id] = .score(min(max(value, 0), Double(levels.count - 1)), confidence: (answer["confidence"] as? Double) ?? 0)
            }
        }
        return out
    }

    /// The best of `options` for `state`, and how sure Jev is. `hints` describes options whose name isn't enough.
    func choose(_ options: [String], hints: [String: String] = [:], for state: [String: String], instructions: String) async throws -> Choice {
        guard let choice = try await ask(["pick": .choice(options, hints: hints, instructions: instructions)], about: state)["pick"]?.choice else {
            throw Failure(message: "Unexpected answer from TypeSafe")
        }
        return choice
    }

    private func post(_ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = switch status {
            case 401: "TypeSafe didn't accept the API key"
            case 422: "TypeSafe refused the request: \(String(decoding: data.prefix(300), as: UTF8.self))"
            case 429, 529: "TypeSafe is busy, will retry later"
            default: "TypeSafe returned \(status)"
            }
            throw Failure(message: message)
        }
        return data
    }

    static func key(for option: String) -> String {
        option.replacingOccurrences(of: ".", with: "_")
    }

    private static func unit(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
              (0...1).contains(n.doubleValue) else { return nil }
        return n.doubleValue
    }

    static func parse(_ data: Data, keys: [String: String]) throws -> Choice {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pick = (json["answers"] as? [String: Any])?["pick"] as? [String: Any] else {
            throw Failure(message: "Unexpected answer from TypeSafe")
        }
        return try choice(pick, keys: keys)
    }

    static func choice(_ pick: [String: Any], keys: [String: String]) throws -> Choice {
        guard let key = pick["choice"] as? String, let option = keys[key] else {
            throw Failure(message: "Unexpected answer from TypeSafe")
        }
        // The distribution is what callers decide on: one that is missing or doesn't add up is an error, never made up.
        guard let raw = pick["probabilities"] as? [String: Any], !raw.isEmpty else {
            throw Failure(message: "TypeSafe's answer has no probabilities")
        }
        var probabilities: [String: Double] = [:]
        for (key, value) in raw {
            guard let option = keys[key], let p = unit(value) else { throw Failure(message: "TypeSafe's probabilities are invalid") }
            probabilities[option] = p
        }
        guard (0.98...1.02).contains(probabilities.values.reduce(0, +)) else {
            throw Failure(message: "TypeSafe's probabilities don't add up")
        }
        return Choice(choice: option, confidence: (pick["confidence"] as? Double) ?? 0, probabilities: probabilities)
    }
}

extension Claude {
    /// The first thing you asked in a session (skipping commands and system notes), from the transcript's head.
    static func firstMessage(head: Data) -> String? {
        for line in head.split(separator: UInt8(ascii: "\n")) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["type"] as? String == "user", obj["isMeta"] as? Bool != true else { continue }
            let content = (obj["message"] as? [String: Any])?["content"]
            let text: String? = (content as? String)
                ?? (content as? [[String: Any]])?.first { $0["type"] as? String == "text" }?["text"] as? String
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, !text.hasPrefix("<") else { continue }
            return String(text.prefix(2000))
        }
        return nil
    }

    static func head(of url: URL, bytes: Int = 256 * 1024) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: bytes)) ?? Data()
    }
}
