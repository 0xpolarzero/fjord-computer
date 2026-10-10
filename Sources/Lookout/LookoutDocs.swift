import Foundation

/// The words the Router reads about Lookout's data, written from the shapes (so they follow the model) and a few worked
/// examples (each checked by a test: it must take, decode and have no problems).
@MainActor
enum LookoutDocs {
    /// Worked examples of a category as the Router writes it (left-out fields are filled in).
    static let examples: [(title: String, json: String)] = [
        ("Review requests", #"{"name":"Review requests","symbol":"eye","color":"amber","rules":[{"scope":{"kind":"pr","to":{"include":[{"me":{}}]},"toRoles":["reviewRequested"]}}]}"#),
        ("My PRs when they need me: someone else commented, checks failing, or open threads", #"{"name":"Mine","symbol":"star","color":"blue","rules":[{"scope":{"kind":"pr","by":{"include":[{"me":{}}]}},"match":"any","conditions":[{"newComment":{"by":{"except":[{"me":{}}]}}},{"checks":{"_0":["failing"]}},{"unresolvedThreads":{}}]}]}"#),
        ("Bots' PRs in repos I own, without notifications", #"{"name":"Bot chatter","symbol":"cpu","color":"gray","notifies":false,"rules":[{"scope":{"kind":"pr","by":{"include":[{"bots":{}}]},"in":{"include":[{"owned":{}}]}}}]}"#),
        ("Failing workflows on main of two repos", #"{"name":"CI on main","symbol":"xmark.seal","color":"red","rules":[{"scope":{"kind":"workflow","in":{"include":[{"repo":{"_0":"acme/api"}},{"repo":{"_0":"acme/web"}}]},"on":["main"]},"conditions":[{"workflow":{"_0":["failing"]}}]}]}"#),
    ]

    /// The grammar of rules, in a few lines, from the shapes.
    static var ruleGrammar: String {
        var lines: [String] = [
            "A category is {id?, name, symbol (SF Symbol), color, rules, notifies, hidden, actions}. A thing (PR, issue or workflow) is in the FIRST category, top to bottom, that one of its rules matches; things no rule matches aren't in the inbox. A rule is {scope, match (any|all), conditions}: the scope says which things, the conditions when they need you (none: every open thing in scope). Left-out fields are filled in: the list says which are required.",
            "",
            "Scope {kind: pr|issue|workflow, by?, to?, toRoles?, in?, on?, named?}. `by`/`to` take PEOPLE, `in` takes REPOS. Workflows need `in`, may have `on` (branches) and `named`, and have no by/to. PRs and issues have by/to/in only. `to` reads the roles in `toRoles` (assigned, reviewRequested, mentioned; issues have no reviewRequested).",
            "People and Repos are {\"include\":[…],\"except\":[…]} (empty include: anyone/anywhere). Where a rule names someone or somewhere, the value is one of:",
            "PERSON:",
        ]
        func variants(_ name: String) {
            guard case .tagged(let list) = Shapes.resolve(.named(name)) else { return }
            for v in list { lines.append("  \(Shapes.example(variant: v)) \(v.doc)") }
        }
        variants("Person")
        lines.append("REPO:")
        variants("Repo")
        lines.append("CONDITION (an object with one key). Each takes {…} as shown; `since` (activity ones) defaults to done:")
        variants("Condition")
        lines.append("Offered by kind: " + ThingKind.allCases.map { kind in
            "\(kind.rawValue): " + RuleEditing.offered(kind).map(RuleEditing.tag).joined(separator: ", ")
        }.joined(separator: "; ") + ".")
        lines += [
            "Impossible rules are refused with the reason, as the editor shows it: a value both included and excepted; a condition the kind doesn't have; contradicting states under `all` (draft and merged, failing and passing); `by me` with approved by me, changes requested by me or `to me` for review requested; teams anywhere but a PR's `to` with reviewRequested; a workflow with no repo; an empty state list; a group of the wrong kind or that doesn't exist; a repo that doesn't exist.",
            "",
            "Examples:",
        ]
        for example in examples { lines.append("- \(example.title): \(example.json)") }
        return lines.joined(separator: "\n")
    }
}
