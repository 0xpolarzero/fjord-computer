import Foundation

/// A rule in the editor's own words, without the editor: the Router's card draws these as read-only chips, and the tools
/// say them in text, so a rule reads the same wherever it is shown.
struct RulePiece: Equatable {
    enum Style: Equatable {
        /// A plain word of the sentence ("by", "when").
        case word
        /// A chosen value.
        case chip
        /// A value that can't match (a group that is gone).
        case danger
    }

    var text: String
    var style: Style

    static func word(_ text: String) -> RulePiece { RulePiece(text: text, style: .word) }
    static func chip(_ text: String, broken: Bool = false) -> RulePiece { RulePiece(text: text, style: broken ? .danger : .chip) }
}

@MainActor
struct RuleWords {
    let data: EditorData

    init(store: Store) { data = EditorData(store: store) }

    /// The rule's lines: its sentence (`PRs by me in Repos I own`), then `when any of:` and one line for each condition.
    func lines(_ rule: Rule) -> [[RulePiece]] {
        let scope = rule.scope
        var sentence: [RulePiece] = [.chip(scope.kinds.label)]
        if !scope.isWorkflow {
            sentence += slot("by", scope.by, person)
            if let to = scope.to {
                let roles = RuleEditing.roles(scope.kinds).filter { scope.toRoles.contains($0) }
                let all = roles.count == RuleEditing.roles(scope.kinds).count
                sentence += slot(all ? "to" : "to (" + roles.map(RuleEditing.roleTitle).joined(separator: ", ") + ")", to, person)
            }
        }
        sentence += slot("in", scope.in, repo)
        if let on = scope.on { sentence += [.word("on")] + (on.isEmpty ? [.chip("default branch")] : on.map { .chip($0) }) }
        if let named = scope.named { sentence += [.word("named")] + (named.isEmpty ? [.chip("any workflow")] : named.map { .chip($0) }) }
        var out = [sentence]
        if rule.conditions.isEmpty { return out }
        var when: [RulePiece] = [.word("when")]
        if rule.conditions.count > 1 { when += [.chip(rule.match.rawValue), .word("of:")] }
        out.append(when)
        out += rule.conditions.map(condition)
        return out
    }

    /// The same, as text: sentences joined by " · ", conditions by "; ".
    func summary(_ rule: Rule) -> String {
        let lines = lines(rule).map { $0.map(\.text).joined(separator: " ") }
        guard lines.count > 1 else { return lines.first ?? "" }
        let conditions = lines.dropFirst(2).joined(separator: "; ")
        return lines[0] + " · " + lines[1] + (conditions.isEmpty ? "" : " " + conditions)
    }

    func summary(_ category: InboxCategory) -> [String] { category.rules.map(summary) }

    // MARK: Pieces

    private func person(_ p: PersonRef) -> RulePiece { .chip(data.personTitle(p), broken: data.isBroken(p)) }
    private func repo(_ r: RepoRef) -> RulePiece { .chip(data.repoTitle(r), broken: data.isBroken(r)) }

    private func slot<V>(_ word: String, _ pick: Pick<V>?, _ piece: (V) -> RulePiece) -> [RulePiece] {
        guard let pick else { return [] }
        return [.word(word)] + values(pick, piece)
    }

    private func values<V>(_ pick: Pick<V>, _ piece: (V) -> RulePiece, anyone: String = "anyone") -> [RulePiece] {
        var out = pick.include.map(piece)
        if out.isEmpty { out = [.chip(anyone)] }
        if !pick.except.isEmpty { out += [.word("except")] + pick.except.map(piece) }
        return out
    }

    private func since(_ s: Since) -> [RulePiece] {
        s == .done ? [] : [.word("since"), .chip(RuleEditing.sinceTitle(s))]
    }

    private func condition(_ c: Condition) -> [RulePiece] {
        var out: [RulePiece] = [.word(c.phrase)]
        switch c {
        case .newComment(let p, let s), .newReview(let p, let s), .newCommits(let p, let s), .mentions(let p, let s):
            out += values(p, person) + since(s)
        case .lastComment(let p), .approved(let p), .changesRequested(let p):
            out += values(p, person)
        case .unresolvedThreads(let started, let last):
            if let started { out += [.word("started by")] + values(started, person) }
            if let last { out += [.word("last reply by")] + values(last, person) }
        case .checks(let states):
            out += CheckState.allCases.filter(states.contains).map { .chip($0.rawValue) }
        case .workflow(let states):
            out += CheckState.allCases.filter(states.contains).map { .chip($0 == .pending ? "running" : $0.rawValue) }
        case .status(let states):
            out += ThingStatus.allCases.filter(states.contains).map { .chip($0 == .open ? "ready" : $0.rawValue) }
        case .labeled(let pick):
            out += values(pick, { .chip($0) }, anyone: "any label")
        case .noActivity(let days):
            out += [.chip("\(days)"), .word("days")]
        case .greptileBelow(let n):
            out += [.chip("\(n) / 5")]
        case .hasConflicts, .behindBase:
            break
        }
        return out
    }
}
