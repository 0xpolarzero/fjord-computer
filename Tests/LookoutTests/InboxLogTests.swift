import Foundation
import Testing
@testable import Lookout

/// The inbox log: every change to the categories and groups is one line naming what changed and who changed it.
@MainActor
@Suite(.serialized) struct InboxLogTests {
    /// A store whose log lines are kept, not written.
    private func store() -> (Store, () -> [String]) {
        let s = InboxFixture.store([InboxFixture.pr(1)])
        s.router.enabled = true
        s.agents.enabled = true
        final class Lines { var all: [String] = [] }
        let lines = Lines()
        s.inboxLog = { lines.all.append($0) }
        return (s, { let out = lines.all; lines.all = []; return out })
    }

    @Test func aDiffSaysWhatWasCreatedChangedDeletedAndReordered() {
        let a = InboxCategory(name: "A", symbol: "eye", color: .red), b = InboxCategory(name: "B", symbol: "star", color: .blue)
        let c = InboxCategory(name: "", symbol: "tray", color: .clay, rules: [Rule(scope: Scope(kinds: [.pr]))])
        var renamed = a
        renamed.name = "A2"
        let lines = InboxLog.categories(from: [a, b], to: [c, renamed], source: .editor)
        #expect(lines.contains { $0.hasPrefix("category created “” \(c.id.uuidString) at 0 [clay, tray, 1 rule(s)] by editor") })
        #expect(lines.contains { $0 == "category updated “A2” \(a.id.uuidString) (was “A”): name by editor" })
        #expect(lines.contains { $0 == "category deleted “B” \(b.id.uuidString) by editor" })
        #expect(!lines.contains { $0.hasPrefix("categories reordered") })
        #expect(InboxLog.categories(from: [a, b], to: [b, a], source: .undo) == ["categories reordered: “B”, “A” by undo"])

        let g = InboxGroup(name: "Friends", kind: .people, members: ["x"])
        var grown = g
        grown.members.append("y")
        #expect(InboxLog.groups(from: [], to: [g], source: .sync) == ["group created “Friends” \(g.id.uuidString) [people, 1 member(s)] by sync"])
        #expect(InboxLog.groups(from: [g], to: [grown], source: .editor) == ["group updated “Friends” \(g.id.uuidString): members (1 → 2) by editor"])
        #expect(InboxLog.groups(from: [g], to: [], source: .revert) == ["group deleted “Friends” \(g.id.uuidString) by revert"])
    }

    @Test func eachChangeIsPutDownToWhoMadeIt() {
        let (s, lines) = store()
        let history = CategoryHistory(store: s)
        var draft = CategoriesView.newDraft(after: s.categories)
        draft.name = "Reviews"
        #expect(s.createCategory(draft, history: history))
        #expect(lines() == [created(draft, at: s.categories.count - 1)])

        s.categories[s.categories.count - 1].notifies = false
        history.observe(s)
        #expect(lines().first?.hasSuffix(": notifies false by editor") == true)
        #expect(history.undo(s))
        #expect(lines() == ["category updated “Reviews” \(draft.id.uuidString): notifies true by undo"])
        #expect(history.redo(s))
        #expect(lines() == ["category updated “Reviews” \(draft.id.uuidString): notifies false by redo"])

        // Nothing changed, nothing said.
        s.categories = s.categories
        #expect(lines().isEmpty)
    }

    @Test func aRouterToolNamesItsDecisionAndARevertIsItsOwn() async {
        let (s, lines) = store()
        let tools = RouterTools(store: s)
        let decision = UUID()
        tools.decision = decision
        tools.beginTurn("make one")
        let result = await tools.call("create_category", ["category": ["name": "My repos", "symbol": "eye", "color": "amber",
                                                                       "rules": [["scope": ["kind": "pr"]]]]])
        #expect(result?.isError == false)
        let made = lines()
        #expect(made.count == 1 && made[0].hasPrefix("category created “My repos”")
                && made[0].hasSuffix("by routerTool(decision: \(decision.uuidString))"))
        #expect(s.inboxSource == nil)

        guard let change = s.router.changes.last else { Issue.record("no change"); return }
        s.revertLookoutChange(change.id)
        #expect(lines().contains { $0.hasPrefix("category deleted “My repos”") && $0.hasSuffix("by revert") })
    }

    private func created(_ c: InboxCategory, at i: Int) -> String {
        "category created “\(c.name)” \(c.id.uuidString) at \(i) [\(c.color.rawValue), \(c.symbol), \(c.rules.count) rule(s)] by newCategoryButton"
    }
}
