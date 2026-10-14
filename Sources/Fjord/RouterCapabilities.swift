import Foundation

// What Fjord's Router can do by itself, with no session: one list. The routing classifier's text (the `change_fjord`
// criteria and `gate_setting`), each run's tool sets and the run's role sentences are all made from it, so a capability
// added here is named, served and explained everywhere, and can't be added in one place and missed in the others.

struct RouterCapability: Equatable {
    var id: String
    /// The run intent that uses it. A compound run takes `changeFjord`'s.
    var intent: RouterRun.Intent
    /// What it does, as the routing classifier is told (nil for a capability that only reads, which routing doesn't name).
    var outcome: String?
    var tools: [String]
    /// What the run's role says about it, in the words its tools use.
    var roleSentence: String?
    /// Out of the run's tools, role and text when Triage is off.
    var needsTriage: Bool = false
}

extension RouterCapability {
    static let all: [RouterCapability] = [
        .init(id: "settings", intent: .changeFjord,
              outcome: "turn a setting on or off, including its notifications",
              tools: ["get_settings", "set_setting"], roleSentence: nil),
        .init(id: "triage-setup", intent: .changeFjord,
              outcome: "change Triage's inbox categories, rules or groups",
              tools: ["list_categories", "get_category", "create_category", "update_category", "delete_category",
                      "reorder_categories", "list_groups", "create_group", "update_group", "delete_group", "list_known"],
              roleSentence: nil, needsTriage: true),
        .init(id: "mark-seen", intent: .changeFjord,
              outcome: "mark a Router card the user has seen or read as seen (a worth-a-look card: \"seen the docs\", \"got it\", \"I read the headlines\")",
              tools: ["mark_seen", "board"],
              roleSentence: "Router cards are what Fjord shows for Claude Code sessions that need the user or are worth a look: you mark one "
                  + "seen with `mark_seen`, for a card worth a look (the `board` tool lists the cards with their tier and whether "
                  + "`canMarkSeen`). The Brief is the short written summary of what needs the user, per project: you can read it "
                  + "through `board`."),
        .init(id: "mark-inbox", intent: .changeFjord,
              outcome: "mark things in the inbox as done or seen",
              tools: ["mark_entries", "list_inbox", "explain_entry"],
              roleSentence: "Triage's inbox things are GitHub PRs, issues and workflows: you mark those with `mark_entries` (done archives "
                  + "them, seen, unread, restore), never with `mark_seen`.",
              needsTriage: true),
        .init(id: "question-board", intent: .question, outcome: nil, tools: ["board", "get_settings"], roleSentence: nil),
        .init(id: "question-triage", intent: .question, outcome: nil,
              tools: ["list_categories", "get_category", "list_groups", "list_inbox", "explain_entry", "list_known"],
              roleSentence: nil, needsTriage: true),
    ]

    /// The capabilities a run of `intent` has (a compound run has a change's), without Triage's when it is off.
    static func available(_ intent: RouterRun.Intent, triage: Bool) -> [RouterCapability] {
        let own: RouterRun.Intent = intent == .compound ? .changeFjord : intent
        return all.filter { $0.intent == own && (triage || !$0.needsTriage) }
    }

    static func toolNames(_ intent: RouterRun.Intent, triage: Bool) -> Set<String> {
        Set(available(intent, triage: triage).flatMap(\.tools))
    }

    /// The role's sentences about what the Router can do, each with a leading space; every run knows them all, whatever
    /// its tools, so "I've seen it" in a question run is understood too.
    static func roleSentences(triage: Bool) -> String {
        all.filter { triage || !$0.needsTriage }.compactMap(\.roleSentence).map { " " + $0 }.joined()
    }

    /// What the routing classifier is told Fjord does itself. It is not told whether Triage is on (the routing questions are
    /// built before the run, and a Triage request with Triage off is refused in the run with a reason), so the full list.
    static var outcomes: String {
        all.filter { $0.intent == .changeFjord }.compactMap(\.outcome).joined(separator: "; ")
    }

    static let notThese = "Not asking a session to build or change code, and not a message for a session to act on (an instruction "
        + "or a reply addressed to it, even one that mentions what the user has seen)"

    /// The `change_fjord` criteria.
    static var changeFjordCriteria: String {
        "Fjord itself does something for the user, without any session: " + outcomes + ". " + notThese
    }

    /// The `gate_setting` question.
    static var settingQuestion: String {
        "Does `message` ask Fjord itself to do something for the user, without any session: " + outcomes
            + "? Not code to be written, and not a message for a session to do or answer something."
    }
}
