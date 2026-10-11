import Foundation

// Sessions that build on each other: a turn whose final message names work under way in another session (its title's words,
// its project) is asked about in the triage's call: does its work depend on that session's? Jev sure of it (p ≥ 0.75), the
// turn waits on that session as an explicit wait would (RouterWaiting.swift): it sits with the working sessions, and once
// the other one finishes its turn it is ready to continue, with Tell it.

enum RouterDepends {
    static let floor = 0.75

    private static let common: Set<String> = ["session", "sessions", "with", "from", "into", "that", "this", "work", "working",
                                              "update", "updates", "change", "changes", "make", "more", "when", "then", "code"]

    /// A title's or a message's words that may name something: four letters or more, the commonest left out.
    static func words(_ text: String) -> Set<String> { RouterCircles.words(text).subtracting(common) }

    /// Whether the message names the other session: two words of its title (all of a shorter one), or its project when it is
    /// another one than the turn's.
    static func names(_ message: String, title: String, project: String, ownProject: String) -> Bool {
        let said = words(message)
        let titled = words(title)
        if !titled.isEmpty, titled.intersection(said).count >= min(2, titled.count) { return true }
        let other = project.lowercased()
        return other.count >= 3 && other != ownProject.lowercased() && message.lowercased().contains(other)
    }

    static func extra(_ options: [RouterTriage.WaitOption]) -> TriageExtra {
        TriageExtra(
            questions: ["buildsOn": .choice(options.map(\.key) + ["none"],
                                            hints: Dictionary(uniqueKeysWithValues: options.map { ($0.key, $0.hint) })
                                                .merging(["none": "None of these"]) { a, _ in a },
                                            instructions: "Does the turn's final message say its work depends on, or builds on, work under way in one of these other sessions, so that it should go on once that one is done? Pick none unless the message clearly says so.")],
            apply: { answers, triage in
                guard let c = answers["buildsOn"]?.choice, (c.probabilities[c.choice] ?? 0) >= floor,
                      let option = options.first(where: { $0.key == c.choice }) else { return }
                switch triage.state {
                case .done, .progress, nil: break
                case .waiting where triage.watch == nil: break
                default: return
                }
                triage.state = .waiting
                triage.waitingOn = .session
                triage.watch = option.watch
            })
    }
}

extension Store {
    /// Asked only when the message names another session at work. Its keys are those of `options`, the wait options Jev is
    /// shown (read once, before the turn's earlier messages were): read again after, the sessions' order may have changed,
    /// and a key would name another session than the one he was shown under it.
    func dependsExtra(_ session: ClaudeSession, message: String, options all: [RouterTriage.WaitOption]) -> TriageExtra? {
        var options: [RouterTriage.WaitOption] = []
        for option in all {
            guard case .session(let id, _) = option.watch.target, let other = claudeSessions[id], other.running,
                  RouterDepends.names(message, title: other.title, project: other.folderName, ownProject: session.folderName) else { continue }
            options.append(option)
        }
        return options.isEmpty ? nil : RouterDepends.extra(options)
    }
}
