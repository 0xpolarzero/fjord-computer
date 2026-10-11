import Foundation
import Testing
@testable import Lookout

/// The Router's second surface, Lookout itself: its tools' schemas, what each change applies and refuses, the record each
/// leaves in the history and what taking it back restores.
@MainActor
@Suite(.serialized) struct RouterLookout {
    private let me = "me"

    /// A store with the default CI category (and "Mine", which holds PRs with a low Greptile score, when asked).
    private func store(things: [Thing] = [], mine: Bool = false) -> Store {
        let s = InboxFixture.store(things)
        s.categories = [InboxStore.ci] + (mine ? [InboxFixture.category()] : [])
        s.router.enabled = true
        s.agents.enabled = true
        return s
    }

    private func tools(_ s: Store, turn: String? = "do it") -> RouterTools {
        let t = RouterTools(store: s)
        if let turn { t.beginTurn(turn) }
        return t
    }

    @discardableResult
    private func call(_ t: RouterTools, _ name: String, _ args: [String: Any]) async -> (ok: Bool, text: String, json: [String: Any]) {
        let result = await t.call(name, args)
        let text = result?.text ?? "unknown tool"
        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        return (result != nil && result?.isError == false, text, json)
    }

    private func category(_ name: String, rules: [[String: Any]] = [], extra: [String: Any] = [:]) -> [String: Any] {
        var c: [String: Any] = ["name": name, "symbol": "eye", "color": "amber", "rules": rules]
        for (k, v) in extra { c[k] = v }
        return c
    }

    private let prByMe: [String: Any] = ["scope": ["kinds": ["pr"], "by": ["include": [["me": [String: Any]()]]]]]

    private var changes: (Store) -> [LookoutChange] { { $0.router.changes } }

    // MARK: Schemas and grammar

    private func check(_ schema: Any, defs: [String: Any], path: String) {
        guard let node = schema as? [String: Any] else { Issue.record("\(path) isn't an object"); return }
        if let ref = node["$ref"] as? String {
            #expect(defs[String(ref.dropFirst("#/$defs/".count))] != nil, "\(path): \(ref) doesn't resolve")
            return
        }
        if let any = node["anyOf"] as? [Any] {
            #expect(!any.isEmpty, "\(path) has an empty anyOf")
            any.enumerated().forEach { check($1, defs: defs, path: "\(path).anyOf[\($0)]") }
            return
        }
        if let all = node["allOf"] as? [Any] { all.forEach { check($0, defs: defs, path: path) }; return }
        guard let type = node["type"] as? String else { return }
        #expect(["object", "array", "string", "integer", "boolean", "number"].contains(type), "\(path): type \(type)")
        if type == "object" {
            let properties = node["properties"] as? [String: Any] ?? [:]
            for name in node["required"] as? [String] ?? [] { #expect(properties[name] != nil, "\(path): required \(name) isn't a property") }
            for (name, sub) in properties { check(sub, defs: defs, path: "\(path).\(name)") }
        }
        if type == "array" { check(node["items"] as Any, defs: defs, path: "\(path)[]") }
    }

    @Test func everyToolHasAValidSchemaAndADescription() throws {
        let specs = RouterTools.specs
        let names = specs.compactMap { $0["name"] as? String }
        #expect(Set(names).count == names.count, "tool names repeat")
        for name in LookoutTools.names { #expect(names.contains(name)) }
        for spec in specs {
            let name = spec["name"] as? String ?? "?"
            #expect((spec["description"] as? String)?.isEmpty == false, "\(name) has no description")
            let schema = try #require(spec["inputSchema"] as? [String: Any])
            #expect(schema["type"] as? String == "object", "\(name)")
            check(schema, defs: schema["$defs"] as? [String: Any] ?? [:], path: name)
            // What the client sends over the wire.
            #expect(JSONSerialization.isValidJSONObject(spec))
        }
        let create = try #require(specs.first { $0["name"] as? String == "create_category" })
        #expect((create["description"] as? String)?.contains("{\"me\": {}}") == true, "the grammar is in the description")
    }

    /// One of each, so a case added to the model without a place in the grammar fails here.
    private var conditions: [Condition] {
        let anyone = Pick<PersonRef>(include: [.me], except: [.bots])
        return [.newComment(by: anyone, since: .myLastComment), .newReview(by: anyone, since: .myLastReview), .newCommits(by: anyone),
                .mentions(anyone, since: .done), .lastComment(by: anyone), .unresolvedThreads(startedBy: anyone, lastReplyBy: nil),
                .approved(by: anyone), .changesRequested(by: anyone), .checks([.failing, .pending]), .hasConflicts, .behindBase,
                .status([.draft, .merged]), .labeled(Pick(include: ["bug"])), .noActivity(days: 3), .greptileBelow(4),
                .asksMe, .noise(true), .noise(false), .importance(.high), .workflow([.failing])]
    }

    @Test func theGrammarHasEveryCaseOfTheModelAndReadsWhatItWrites() throws {
        guard case .tagged(let variants) = Shapes.resolve(.named("Condition")) else { Issue.record("no Condition shape"); return }
        #expect(Set(variants.map(\.tag)) == Set(conditions.map(RuleEditing.tag)))
        for condition in conditions {
            let object = LookoutJSON.object(condition)
            let normalized = try Shapes.normalize(object, as: .named("Condition"))
            #expect(try LookoutJSON.decode(Condition.self, from: normalized) == condition, "\(condition)")
        }
        let people: [PersonRef] = [.me, .user("a"), .group(UUID()), .maintainers, .bots, .team("o/t"), .myTeams]
        let repos: [RepoRef] = [.repo("a/b"), .owner("a"), .group(UUID()), .owned, .contributed, .involved]
        guard case .tagged(let personVariants) = Shapes.resolve(.named("Person")),
              case .tagged(let repoVariants) = Shapes.resolve(.named("Repo")) else { return }
        func tag(_ p: PersonRef) -> String {
            switch p {
            case .me: "me"
            case .user: "user"
            case .group: "group"
            case .maintainers: "maintainers"
            case .bots: "bots"
            case .team: "team"
            case .myTeams: "myTeams"
            }
        }
        func tag(_ r: RepoRef) -> String {
            switch r {
            case .repo: "repo"
            case .owner: "owner"
            case .group: "group"
            case .owned: "owned"
            case .contributed: "contributed"
            case .involved: "involved"
            }
        }
        #expect(Set(personVariants.map(\.tag)) == Set(people.map(tag)))
        #expect(Set(repoVariants.map(\.tag)) == Set(repos.map(tag)))
        for p in people {
            let n = try Shapes.normalize(LookoutJSON.object(p), as: .named("Person"))
            #expect(try LookoutJSON.decode(PersonRef.self, from: n) == p)
        }
        for r in repos {
            let n = try Shapes.normalize(LookoutJSON.object(r), as: .named("Repo"))
            #expect(try LookoutJSON.decode(RepoRef.self, from: n) == r)
        }
        // The action kinds come from the model's own encoding.
        let actions = [CategoryAction.make(.askRouter(prompt: "go")), .make(.comment("hi")), .make(.rerun)]
        for action in actions {
            let n = try Shapes.normalize(LookoutJSON.object(action), as: .named("Action"))
            #expect(try LookoutJSON.decode(CategoryAction.self, from: n).kind == action.kind)
        }
        // A whole category the model makes is a category the shape takes.
        let offered = Set(RuleEditing.offered([.pr]).map(RuleEditing.tag))
        let prConditions = conditions.filter { offered.contains(RuleEditing.tag($0)) }
        var all = InboxCategory(name: "All", symbol: "star", color: .blue)
        all.rules = [Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.me]), to: Pick(include: [.team("o/t")]), toRoles: [.reviewRequested],
                                       in: Pick(include: [.involved])), match: .all, conditions: prConditions),
                     Rule(scope: Scope(kinds: [.workflow], in: Pick(include: [.repo("a/b")]), on: ["main"], named: ["ci"]), conditions: [.workflow([.failing])])]
        all.actions = ActionList(actions)
        let n = try Shapes.normalize(LookoutJSON.object(all), as: .named("Category"))
        #expect(try LookoutJSON.decode(InboxCategory.self, from: n).rules.count == 2)
    }

    @Test func theWorkedExamplesAreTakenAndHaveNoProblems() throws {
        let s = store()
        for example in LookoutDocs.examples {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(example.json.utf8)) as? [String: Any])
            let n = try Shapes.normalize(object, as: .named("Category"))
            let c = try LookoutJSON.decode(InboxCategory.self, from: n)
            #expect(LookoutValidate.category(c, old: nil, in: s).isEmpty, "\(example.title): \(LookoutValidate.category(c, old: nil, in: s))")
        }
    }

    @Test func whatIsWrongInTheInputIsSaidByWhere() throws {
        func fails(_ value: Any, _ shape: JSONShape, _ words: String) {
            #expect(throws: ShapeError.self) { try Shapes.normalize(value, as: shape) }
            do { _ = try Shapes.normalize(value, as: shape) } catch { #expect("\(error.localizedDescription)".contains(words), "\(error.localizedDescription)") }
        }
        fails(["name": "x", "symbol": "eye", "color": "pink"], .named("Category"), "color")
        fails(["name": "x", "symbol": "eye", "color": "red", "colour": "red"], .named("Category"), "colour")
        fails(["name": "x", "symbol": "eye", "color": "red", "rules": [["scope": ["kinds": ["pr"]], "conditions": [["chekcs": [String: Any]()]]]]],
              .named("Category"), "rules[0].conditions[0]")
        fails(["name": "x", "symbol": "eye", "color": "red", "rules": [["scope": ["kinds": ["pr"], "by": ["include": [["me": "yes"]]]]]]],
              .named("Category"), "takes no value")
        fails(["symbol": "eye", "color": "red"], .named("Category"), "name: is missing")
    }

    // MARK: Categories

    @Test func creatingACategoryAppliesAtOnceAndLeavesACard() async throws {
        let s = store()
        let history = CategoryHistory(store: s)
        s.categoryHistory = history
        let t = tools(s)
        let rules = [prByMe.merging(["conditions": [["checks": ["_0": ["failing"]]]]]) { a, _ in a }]
        let out = await call(t, "create_category", ["category": category("Mine", rules: rules)])
        #expect(out.ok, "\(out.text)")
        let made = try #require(s.categories.last)
        #expect(made.name == "Mine" && made.notifies && !made.hidden && !made.isCI && made.rules.count == 1)
        #expect(made.rules[0].conditions == [.checks([.failing])] && made.rules[0].scope.toRoles == Set(ToRole.allCases))
        #expect(s.categories.count == 2, "the default CI category is kept")

        let change = try #require(s.router.changes.last)
        #expect(change.title == "Created category Mine" && !change.isReverted)
        guard case .category(let index, let before, let after) = change.patch else { Issue.record("not a category patch"); return }
        #expect(index == 1 && before == nil && after == made)
        // The editor's history knows nothing of it: ⌘Z can't take it back, only the card.
        #expect(!history.canUndo)
        #expect(out.json["changeId"] as? String == change.id.uuidString)
    }

    @Test func aCategoryCanBePlacedFirst() async throws {
        let s = store()
        let out = await call(tools(s), "create_category", ["category": category("First", rules: [prByMe]), "at": 0])
        #expect(out.ok && s.categories.map(\.name) == ["First", "CI"], "\(out.text)")
    }

    private func refused(_ s: Store, _ args: [String: Any], _ words: [String], sourceLocation: SourceLocation = #_sourceLocation) async {
        let before = s.categories, logged = s.router.changes.count
        let out = await call(tools(s), "create_category", ["category": args])
        #expect(!out.ok, "\(args)", sourceLocation: sourceLocation)
        for word in words { #expect(out.text.contains(word), "“\(word)” missing from: \(out.text)", sourceLocation: sourceLocation) }
        #expect(s.categories == before && s.router.changes.count == logged, "nothing changes", sourceLocation: sourceLocation)
    }

    @Test func rulesThatCanNeverMatchAreRefusedWithTheEditorsReasons() async {
        let s = store()
        func rule(_ scope: [String: Any], _ conditions: [[String: Any]] = [], match: String = "any") -> [String: Any] {
            ["scope": scope, "conditions": conditions, "match": match]
        }
        let me: [String: Any] = ["me": [String: Any]()]
        // A value both included and excepted.
        await refused(s, category("A", rules: [rule(["kinds": ["pr"], "by": ["include": [me], "except": [me]]])]),
                      ["“by”", "both included and excepted"])
        // A condition the kind doesn't have.
        await refused(s, category("B", rules: [rule(["kinds": ["issue"]], [["greptileBelow": ["_0": 3]]])]), ["conditions[0]", "Issues don't have this"])
        // Contradicting states under all-of.
        await refused(s, category("C", rules: [rule(["kinds": ["pr"]], [["status": ["_0": ["draft"]]], ["status": ["_0": ["merged"]]]], match: "all")]),
                      ["Contradicts the other status"])
        // Nobody reviews their own PR.
        await refused(s, category("D", rules: [rule(["kinds": ["pr"], "by": ["include": [me]]], [["approved": ["by": ["include": [me]]]]])]),
                      ["GitHub doesn't let you review your own PR"])
        // A workflow with no repo; a PR with a branch.
        await refused(s, category("E", rules: [rule(["kinds": ["workflow"]], [["workflow": ["_0": ["failing"]]]])]), ["Workflows need a repository"])
        await refused(s, category("F", rules: [rule(["kinds": ["pr"], "on": ["main"]])]), ["Only workflows have branches"])
        // A team outside `to`; an empty state list; an unknown group.
        await refused(s, category("G", rules: [rule(["kinds": ["pr"], "by": ["include": [["team": ["_0": "o/t"]]]]])]), ["Teams don't author anything"])
        await refused(s, category("H", rules: [rule(["kinds": ["pr"]], [["checks": ["_0": [String]()]]])]), ["Pick at least one state"])
        await refused(s, category("I", rules: [rule(["kinds": ["pr"], "by": ["include": [["group": ["_0": UUID().uuidString]]]]])]), ["This group no longer exists"])
        // Not an SF Symbol, a name taken, no name; an unknown field or colour.
        await refused(s, category("J", extra: ["symbol": "not.a.symbol"]), ["isn't an SF Symbol"])
        await refused(s, category("ci"), ["called “ci” already"])
        await refused(s, category("  "), ["`name` is empty"])
        await refused(s, category("K", extra: ["color": "pink"]), ["color", "one of"])
        // Several reasons together.
        await refused(s, category("L", rules: [rule(["kinds": ["issue"], "on": ["main"]], [["greptileBelow": ["_0": 3]], ["checks": ["_0": [String]()]]])]),
                      ["Only workflows have branches", "conditions[0]", "conditions[1]"])
        // CI can't be made, and an action that applies to nothing is refused.
        await refused(s, category("M", extra: ["isCI": true]), ["`isCI`"])
        await refused(s, category("N", rules: [rule(["kinds": ["issue"]])], extra: ["actions": [["kind": ["rerun": [String: Any]()]]]]),
                      ["Re-run failed checks", "None of this category's rules"])
    }

    @Test func oneRuleTakesPRsAndIssuesAndTheOldSingleKindStillReads() async throws {
        let s = store()
        let to: [String: Any] = ["include": [["me": [String: Any]()]]]
        let made = await call(tools(s), "create_category", ["category": category("Mine", rules: [
            ["scope": ["kinds": ["issue", "pr"], "to": to]],
            // The form rules once had: one `kind`, and no roles said, so an issue gets no review requested.
            ["scope": ["kind": "issue", "to": to]],
        ])])
        #expect(made.ok, "\(made.text)")
        let rules = try #require(s.categories.first { $0.name == "Mine" }).rules
        #expect(rules.map(\.scope.kinds) == [[.pr, .issue], [.issue]])
        #expect(rules[0].scope.toRoles == Set(ToRole.allCases) && rules[1].scope.toRoles == [.assigned, .mentioned])
        await refused(s, category("Mixed", rules: [["scope": ["kinds": ["pr", "workflow"], "in": ["include": [[String: Any]]()]]]]),
                      ["Workflows are a rule of their own"])
        await refused(s, category("Both", rules: [["scope": ["kinds": ["pr", "issue"]], "conditions": [["hasConflicts": [String: Any]()]]]]),
                      ["Issues don't have this"])
    }

    @Test func aGroupOfTheWrongKindOrATeamOutsideToIsRefused() async {
        let s = store()
        let peopleGroup = InboxGroup(name: "Crew", kind: .people, members: ["a"])
        s.groups = [peopleGroup]
        await refused(s, category("A", rules: [["scope": ["kinds": ["pr"], "in": ["include": [["group": ["_0": peopleGroup.id.uuidString]]]]]]]),
                      ["people group"])
        await refused(s, category("B", rules: [["scope": ["kinds": ["pr"]], "conditions": [["lastComment": ["by": ["include": [["myTeams": [String: Any]()]]]]]]]]),
                      ["Teams only go in `to`"])
        await refused(s, category("C", rules: [["scope": ["kinds": ["issue"], "to": ["include": [["me": [String: Any]()]]], "toRoles": ["reviewRequested"]]]]),
                      ["Only PRs have review requests"])
    }

    @Test func updatingKeepsWhatIsLeftOutAndEachRulesHistory() async throws {
        let s = store()
        let t = tools(s)
        await call(t, "create_category", ["category": category("Mine", rules: [prByMe], extra: ["notifies": false])])
        let original = try #require(s.categories.last)
        let old = Date(timeIntervalSince1970: 1_000_000)
        s.categories[1].rules[0].createdAt = old
        t.beginTurn("update")
        let out = await call(t, "update_category", ["category": ["id": original.id.uuidString, "color": "green",
                                                                 "rules": [["id": original.rules[0].id.uuidString, "scope": ["kinds": ["pr"]]]]]])
        #expect(out.ok, "\(out.text)")
        let now = try #require(s.categories.last)
        #expect(now.color == .green && now.name == "Mine" && !now.notifies && now.symbol == "eye")
        #expect(now.rules[0].id == original.rules[0].id && Int(now.rules[0].createdAt.timeIntervalSince1970) == 1_000_000)
        #expect(now.rules[0].scope.by == nil, "the rules given replace the list")
        #expect(changes(s).last?.title == "Changed category Mine")
        // Nothing to change says so, and leaves no card.
        let count = changes(s).count
        let same = await call(t, "update_category", ["category": ["id": now.id.uuidString]])
        #expect(same.ok && same.json["changed"] as? String == "nothing" && changes(s).count == count)
        // Unknown ids and missing ids are refused.
        #expect(await call(t, "update_category", ["category": ["id": UUID().uuidString]]).ok == false)
        #expect(await call(t, "update_category", ["category": ["name": "x"]]).ok == false)
    }

    @Test func theCICategoryKeepsToItsOneJob() async throws {
        let s = store()
        let ci = try #require(s.categories.first)
        let t = tools(s)
        let rename = await call(t, "update_category", ["category": ["id": ci.id.uuidString, "hidden": true, "name": "Pipelines"]])
        #expect(rename.ok && s.categories[0].hidden && s.categories[0].name == "Pipelines" && s.categories[0].isCI)
        let bad = await call(t, "update_category", ["category": ["id": ci.id.uuidString, "rules": [["scope": ["kinds": ["pr"]]]]]])
        #expect(!bad.ok && bad.text.contains("CI category only has workflow rules"))
        #expect(await call(t, "update_category", ["category": ["id": ci.id.uuidString, "isCI": false]]).ok == false)
        let delete = await call(t, "delete_category", ["category": ci.id.uuidString])
        #expect(delete.ok && delete.json["waiting"] as? String == "Deleted category Pipelines" && s.categories.count == 1)
        s.applyLookoutChange(try #require(changes(s).last).id)
        #expect(s.categories.isEmpty)
        // And the tool says so.
        let doc = try #require(LookoutTools.tools.first { $0.name == "delete_category" }?.doc)
        #expect(doc.contains("the CI category too") && !doc.contains("can't be deleted"))
    }

    @Test func revertingPutsBackOnlyThatCategory() async throws {
        let s = store()
        let t = tools(s)
        await call(t, "create_category", ["category": category("One", rules: [prByMe])])
        await call(t, "create_category", ["category": category("Two", rules: [prByMe])])
        let one = try #require(s.categories.first { $0.name == "One" })
        t.beginTurn("rename it")
        await call(t, "update_category", ["category": ["id": one.id.uuidString, "name": "Uno", "color": "red"]])
        let two = try #require(s.categories.first { $0.name == "Two" })
        let renamed = try #require(changes(s).last)
        #expect(renamed.title == "Renamed category One to Uno" || renamed.title == "Changed category Uno")

        let reverted = try #require(s.revertLookoutChange(renamed.id))
        #expect(reverted.revertNote == "Reverted" && reverted.isReverted)
        #expect(s.categories.first { $0.id == one.id } == one, "back to what it was")
        #expect(s.categories.first { $0.id == two.id } == two, "the other one is not touched")
        #expect(s.router.changes.last?.isReverted == true, "the card in the history says so")
        #expect(s.revertLookoutChange(renamed.id) == nil, "once")
        // Taking back a creation removes it.
        let created = try #require(changes(s).first)
        s.revertLookoutChange(created.id)
        #expect(!s.categories.contains { $0.id == one.id })
    }

    @Test func revertingAfterALaterEditUndoesTheLaterEditsToo() async throws {
        let s = store()
        let t = tools(s)
        await call(t, "create_category", ["category": category("Mine", rules: [prByMe])])
        let made = try #require(s.categories.last)
        t.beginTurn("recolor it")
        await call(t, "update_category", ["category": ["id": made.id.uuidString, "color": "blue"]])
        let first = try #require(changes(s).first)
        let second = try #require(changes(s).last)
        // By hand, in the editor, after both.
        s.categories[1].name = "Edited by hand"
        let note = try #require(s.revertLookoutChange(second.id)).revertNote
        #expect(note == "Reverted (later edits to it were undone too)")
        #expect(s.categories[1] == made, "back to its state before the change, the hand edit gone")
        // The first change: the category is as it made it, so nothing was edited since it... but a later change was.
        s.categories[1].notifies = false
        #expect(s.revertLookoutChange(first.id)?.revertNote == "Reverted (later edits to it were undone too)")
        #expect(!s.categories.contains { $0.id == made.id })
    }

    // MARK: One run, one record

    @discardableResult
    private func update(_ t: RouterTools, _ c: InboxCategory, _ fields: [String: Any]) async -> [String: Any] {
        var category = fields
        category["id"] = c.id.uuidString
        return await call(t, "update_category", ["category": category]).json
    }

    @Test func creatingThenEditingInOneRunIsOneCreatedRecord() async throws {
        let s = store()
        let t = tools(s)
        let run = RouterDecision(trigger: .you("make it"), decision: .init(intent: "make it"), outcome: .pending)
        _ = s.logDecision(run)
        t.decision = run.id
        let first = await call(t, "create_category", ["category": category("My repos", rules: [prByMe])])
        let made = try #require(s.categories.last)
        let second = await update(t, made, ["rules": [["scope": ["kinds": ["pr"]]]]])
        #expect(second["changeId"] as? String == first.json["changeId"] as? String, "the same record")
        #expect(changes(s).count == 1)
        let record = try #require(changes(s).first)
        #expect(record.title == "Created category My repos")
        guard case .category(_, let before, let after) = record.patch else { Issue.record("not a category"); return }
        #expect(before == nil && after == s.categories.last, "the final state")
        let entry = try #require(s.router.decisions.first { $0.id == run.id })
        #expect(entry.done.filter { if case .changed = $0 { true } else { false } }.count == 1 && entry.links.changes == [record.id])
        // Taking it back removes the category.
        let reverted = try #require(s.revertLookoutChange(record.id))
        #expect(reverted.revertNote == "Reverted" && !s.categories.contains { $0.id == made.id })
    }

    @Test func editingTwiceInOneRunIsOneChangeFromTheFirstBeforeToTheLastAfter() async throws {
        let s = store()
        let t = tools(s)
        await call(t, "create_category", ["category": category("Mine", rules: [prByMe])])
        let original = try #require(s.categories.last)
        t.beginTurn("two edits")
        await update(t, original, ["color": "blue"])
        let mid = try #require(s.categories.last)
        await update(t, mid, ["symbol": "bell"])
        #expect(changes(s).count == 2, "the creation (an earlier run) and one change")
        let record = try #require(changes(s).last)
        #expect(record.title == "Changed category Mine")
        guard case .category(_, let before, let after) = record.patch else { Issue.record("not a category"); return }
        #expect(before == original && after == s.categories.last)
        s.revertLookoutChange(record.id)
        #expect(s.categories.last == original)
    }

    @Test func creatingThenDeletingInOneRunLeavesNothing() async throws {
        let s = store()
        let t = tools(s)
        let run = RouterDecision(trigger: .you("make it"), decision: .init(intent: "make it"), outcome: .pending)
        _ = s.logDecision(run)
        t.decision = run.id
        await call(t, "create_category", ["category": category("Oops", rules: [prByMe])])
        let made = try #require(s.categories.last)
        let gone = await call(t, "delete_category", ["category": made.id.uuidString])
        #expect(gone.ok && gone.json["changed"] as? String == "nothing")
        #expect(changes(s).isEmpty && !s.categories.contains { $0.id == made.id })
        let entry = try #require(s.router.decisions.first { $0.id == run.id })
        #expect(entry.done.isEmpty && entry.links.changes.isEmpty)
    }

    @Test func editingBackToTheOriginalInOneRunLeavesNothing() async throws {
        let s = store()
        let t = tools(s)
        await call(t, "create_category", ["category": category("Mine", rules: [prByMe])])
        let original = try #require(s.categories.last)
        t.beginTurn("flip")
        await update(t, original, ["color": "blue"])
        let back = await update(t, original, ["color": original.color.rawValue])
        #expect(back["changed"] as? String == "nothing")
        #expect(changes(s).count == 1, "only the creation of the earlier run")
        #expect(s.categories.last == original)
    }

    @Test func editingThenDeletingInOneRunIsOneDeletedFromTheFirstBefore() async throws {
        let s = store()
        let t = tools(s)
        await call(t, "create_category", ["category": category("Mine", rules: [prByMe])])
        let original = try #require(s.categories.last)
        t.beginTurn("edit and delete")
        await update(t, original, ["color": "blue"])
        let edited = try #require(s.categories.last)
        await call(t, "delete_category", ["category": original.id.uuidString])
        // The deletion waits for Apply, on a card of its own: nothing joins a waiting change.
        let record = try #require(changes(s).last)
        #expect(changes(s).count == 3 && record.title == "Deleted category Mine" && record.isPending)
        #expect(s.categories.last == edited)
        s.applyLookoutChange(record.id)
        #expect(!s.categories.contains { $0.id == original.id })
        s.revertLookoutChange(record.id)
        #expect(s.categories.last == edited)
    }

    @Test func changesInDifferentRunsOrToDifferentThingsStaySeparate() async throws {
        let s = store()
        let t = tools(s)
        await call(t, "create_category", ["category": category("One", rules: [prByMe])])
        await call(t, "create_category", ["category": category("Two", rules: [prByMe])])
        #expect(changes(s).count == 2)
        let one = try #require(s.categories.first { $0.name == "One" })
        t.beginTurn("later")
        await update(t, one, ["color": "blue"])
        #expect(changes(s).count == 3)
    }

    @Test func deletingAndRevertingBringsItBackWhereItWas() async throws {
        let s = store()
        let t = tools(s)
        await call(t, "create_category", ["category": category("A", rules: [prByMe])])
        await call(t, "create_category", ["category": category("B", rules: [prByMe])])
        await call(t, "create_category", ["category": category("C", rules: [prByMe])])
        let b = try #require(s.categories.first { $0.name == "B" })
        t.beginTurn("delete")
        let out = await call(t, "delete_category", ["category": "b"])
        let card = try #require(changes(s).last)
        #expect(out.ok && card.title == "Deleted category B" && card.isPending)
        s.applyLookoutChange(card.id)
        #expect(!s.categories.contains { $0.id == b.id })
        s.revertLookoutChange(card.id)
        #expect(s.categories.map(\.name) == ["CI", "A", "B", "C"] && s.categories[2] == b)
    }

    @Test func reorderingNeedsEveryCategoryAndCanBeReverted() async throws {
        let s = store()
        let t = tools(s)
        await call(t, "create_category", ["category": category("A", rules: [prByMe])])
        let before = s.categories.map(\.id)
        let partial = await call(t, "reorder_categories", ["order": ["A"]])
        #expect(!partial.ok && partial.text.contains("CI"))
        let out = await call(t, "reorder_categories", ["order": ["A", "CI"]])
        #expect(out.ok && s.categories.map(\.name) == ["A", "CI"])
        s.revertLookoutChange(try #require(changes(s).last).id)
        #expect(s.categories.map(\.id) == before)
        #expect(await call(t, "reorder_categories", ["order": ["A", "Nope"]]).ok == false)
    }

    // MARK: Groups

    @Test func groupsAreCreatedChangedAndDeletedUnderTheEditorsRules() async throws {
        let s = store()
        let t = tools(s)
        let made = await call(t, "create_group", ["group": ["name": "Crew", "kind": "people", "members": ["@alice", "bob", "alice"]]])
        #expect(made.ok, "\(made.text)")
        let group = try #require(s.groups.first)
        #expect(group.members == ["alice", "bob"] && changes(s).last?.title == "Created group Crew")
        #expect(await call(t, "create_group", ["group": ["name": "crew", "kind": "people"]]).text.contains("already"))
        #expect(await call(t, "create_group", ["group": ["name": "Repos", "kind": "repos", "members": ["nope"]]]).text.contains("isn't a repo"))
        #expect(await call(t, "create_group", ["group": ["name": "People", "kind": "people", "members": ["a/b"]]]).ok == false)
        // Used by a rule: its kind can't change and it can't be deleted.
        let rule: [String: Any] = ["scope": ["kinds": ["pr"], "by": ["include": [["group": ["_0": group.id.uuidString]]]]]]
        #expect(await call(t, "create_category", ["category": category("Crew PRs", rules: [rule])]).ok)
        let kind = await call(t, "update_group", ["group": ["id": group.id.uuidString, "kind": "repos"]])
        #expect(!kind.ok && kind.text.contains("Crew PRs"))
        let delete = await call(t, "delete_group", ["group": "Crew"])
        #expect(!delete.ok && delete.text.contains("Crew PRs") && s.groups.count == 1)
        // Members are replaced as a list; the rule follows the group.
        t.beginTurn("members")
        let update = await call(t, "update_group", ["group": ["id": group.id.uuidString, "members": ["carol"]]])
        #expect(update.ok && s.groups[0].members == ["carol"] && s.groups[0].name == "Crew")
        s.revertLookoutChange(try #require(changes(s).last).id)
        #expect(s.groups[0].members == ["alice", "bob"])
        // Unused, it goes, and comes back.
        s.categories.removeAll { $0.name == "Crew PRs" }
        t.beginTurn("delete it")
        #expect(await call(t, "delete_group", ["group": group.id.uuidString]).ok && s.groups.count == 1)
        s.applyLookoutChange(try #require(changes(s).last).id)
        #expect(s.groups.isEmpty)
        s.revertLookoutChange(try #require(changes(s).last).id)
        #expect(s.groups.first?.id == group.id)
    }

    // MARK: Settings

    @Test func onlyTheUserFacingSettingsCanBeChanged() async throws {
        let s = store()
        let t = tools(s)
        let keys = LookoutSetting.all.map(\.key)
        #expect(Set(keys) == ["notifications", "snooze", "pollInterval", "centerBar", "launchAtLogin", "sessionIcons"])
        let listed = await call(t, "get_settings", [:])
        #expect((listed.json["settings"] as? [[String: Any]])?.compactMap { $0["key"] as? String } == keys)
        for refused in ["token", "account", "quit", "router", "routerEnabled", "typesafeKey", "enabled", "skippedVersion"] {
            let out = await call(t, "set_setting", ["key": refused, "value": true])
            #expect(!out.ok, "\(refused)")
        }
        #expect(s.router.enabled && s.settings.notifications)

        t.beginTurn("turn off notifications, snooze for an hour, check every 2 minutes and center the bar")
        let off = await call(t, "set_setting", ["key": "notifications", "value": false])
        #expect(off.ok && !s.settings.notifications && changes(s).last?.title == "Turned off desktop notifications")
        #expect(await call(t, "set_setting", ["key": "notifications", "value": "no"]).ok == false)
        #expect(await call(t, "set_setting", ["key": "notifications", "value": false]).json["changed"] as? String == "nothing")

        let snooze = await call(t, "set_setting", ["key": "snooze", "value": "1h"])
        #expect(snooze.ok && s.isSnoozed && changes(s).last?.title == "Changed snooze to 1 hour")
        let poll = await call(t, "set_setting", ["key": "pollInterval", "value": 120])
        #expect(poll.ok && s.settings.pollInterval == 120 && changes(s).last?.title == "Changed check interval to 2 minutes")
        #expect(await call(t, "set_setting", ["key": "pollInterval", "value": 7]).ok == false)
        #expect(await call(t, "set_setting", ["key": "snooze", "value": "forever"]).ok == false)
        let center = await call(t, "set_setting", ["key": "centerBar", "value": true])
        #expect(center.ok && s.settings.centerPill == true)

        // Taking back restores the value before, and only it.
        s.revertLookoutChange(try #require(changes(s).first { $0.title.hasPrefix("Changed snooze") }).id)
        #expect(!s.isSnoozed && s.settings.pollInterval == 120 && s.settings.centerPill == true)
        s.revertLookoutChange(try #require(changes(s).first { $0.title.hasPrefix("Turned off") }).id)
        #expect(s.settings.notifications)
    }

    @Test func theLoginItemAndSessionIconsGoThroughTheirOwnSwitches() async throws {
        let s = store()
        var login = false
        let saved = LookoutSetting.launchAtLogin
        LookoutSetting.launchAtLogin = ({ login }, { login = $0 })
        defer { LookoutSetting.launchAtLogin = saved }
        let t = tools(s, turn: "launch at login, and pick icons for sessions")
        #expect(await call(t, "set_setting", ["key": "launchAtLogin", "value": true]).ok && login)
        s.revertLookoutChange(try #require(changes(s).last).id)
        #expect(!login)
        // Session titles go to TypeSafe: that waits for Apply, asked or not.
        #expect(await call(t, "set_setting", ["key": "sessionIcons", "value": true]).ok && !s.agents.iconsEnabled)
        s.applyLookoutChange(try #require(changes(s).last).id)
        #expect(s.agents.iconsEnabled)
        LookoutSetting.launchAtLogin = ({ login }, { _ in throw CocoaError(.userCancelled) })
        let failed = await call(t, "set_setting", ["key": "launchAtLogin", "value": true])
        #expect(!failed.ok && failed.text.contains("Couldn't change launchAtLogin"))
    }

    // MARK: The inbox

    private func inboxStore() -> Store {
        var other = InboxFixture.pr(2, repo: "a/two", title: "Fix the flaky test", greptile: 2)
        other.author = Person(login: "alice")
        return store(things: [InboxFixture.pr(1, title: "Add the router"), other, InboxFixture.pr(3, greptile: nil)], mine: true)
    }

    @Test func theInboxIsListedFilteredAndExplained() async throws {
        let s = inboxStore()
        let t = tools(s)
        let listed = await call(t, "list_inbox", [:])
        let entries = try #require(listed.json["entries"] as? [[String: Any]])
        #expect(entries.count == 2 && listed.json["count"] as? Int == 2)
        let first = try #require(entries.first { $0["thing"] as? String == "pr:a/one#1" })
        #expect(first["ref"] as? String == "a/one#1" && first["category"] as? String == "Mine" && first["done"] as? Bool == false)
        #expect((first["facts"] as? [String]) == ["Greptile 3/5"])
        let found = await call(t, "list_inbox", ["query": "flaky", "category": "mine"])
        #expect((found.json["entries"] as? [[String: Any]])?.count == 1)
        #expect((await call(t, "list_inbox", ["category": "Nope"])).ok == false)

        let why = await call(t, "explain_entry", ["entry": "a/one#1"])
        #expect(why.ok && (why.json["matched"] as? [String: Any])?["category"] as? String == "Mine")
        let rules = (why.json["matched"] as? [String: Any])?["rules"] as? [[String: Any]]
        #expect(rules?.first?["facts"] as? [String] == ["Greptile 3/5"] && rules?.first?["rule"] as? Int == 0)
        let none = await call(t, "explain_entry", ["entry": "a/one#3"])
        #expect(none.ok && (none.json["inbox"] as? String)?.hasPrefix("not in the inbox") == true && none.json["matched"] == nil)
        #expect(await call(t, "explain_entry", ["entry": "nothing like this"]).ok == false)

        // Shadowed by a category above it: said, with the one that comes after.
        s.categories.insert(InboxCategory(name: "Alice", symbol: "person", color: .green,
                                          rules: [Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.user("alice")])))]), at: 0)
        let shadowed = await call(t, "explain_entry", ["entry": "flaky"])
        #expect((shadowed.json["matched"] as? [String: Any])?["category"] as? String == "Alice")
        #expect((shadowed.json["alsoMatchesButComesAfter"] as? [[String: Any]])?.first?["category"] as? String == "Mine")
    }

    @Test func markingDoneSeenAndRestoreIsOneCardThatRevertsExactly() async throws {
        let s = inboxStore()
        let t = tools(s, turn: "mark them seen, then done")
        let seenBefore = s.marks
        let seen = await call(t, "mark_entries", ["state": "seen", "entries": ["a/one#1"]])
        #expect(seen.ok && changes(s).last?.title == "Marked 1 seen")
        let done = await call(t, "mark_entries", ["state": "done", "category": "Mine"])
        #expect(done.ok && changes(s).last?.title == "Marked 2 done" && s.doneEntries.count == 2)
        #expect(await call(t, "mark_entries", ["state": "done", "category": "Mine"]).json["changed"] as? String == "nothing")
        #expect(s.entries.allSatisfy { $0.isDone })
        let mark = try #require(s.marks["pr:a/one#1"])
        s.revertLookoutChange(try #require(changes(s).last).id)
        #expect(s.doneEntries.isEmpty)
        #expect(s.marks["pr:a/one#1"]?.seen == mark.seen, "what was seen stays seen")
        s.revertLookoutChange(try #require(changes(s).first).id)
        #expect(s.marks == seenBefore)
        let restored = await call(t, "mark_entries", ["state": "restore", "entries": ["pr:a/one#1"]])
        #expect(restored.json["changed"] as? String == "nothing")
        #expect(await call(t, "mark_entries", ["state": "done"]).ok == false, "needs entries or a category")
    }

    @Test func knownValuesAreListedForTheRulesToUse() async throws {
        let s = inboxStore()
        let t = tools(s)
        let repos = await call(t, "list_known", ["kind": "repos", "query": "two"])
        #expect(repos.json["values"] as? [String] == ["a/two"])
        let people = await call(t, "list_known", ["kind": "people"])
        #expect((people.json["values"] as? [String])?.contains("alice") == true && (people.json["special"] as? [String])?.contains("maintainers") == true)
        #expect(await call(t, "list_known", ["kind": "labels"]).ok == false)
    }

    @Test func listsShowCategoriesAndGroupsAsTheEditorTakesThem() async throws {
        let s = inboxStore()
        let t = tools(s)
        let listed = await call(t, "list_categories", [:])
        let categories = try #require(listed.json["categories"] as? [[String: Any]])
        let mine = try #require(categories.first { $0["name"] as? String == "Mine" })
        #expect(mine["open"] as? Int == 2 && (mine["summary"] as? [String])?.first == "PRs · when Greptile score below 5 / 5")
        // What it lists is what update takes back.
        let again = await call(t, "update_category", ["category": mine.filter { ["id", "name", "symbol", "color", "rules", "notifies", "hidden", "isCI", "actions"].contains($0.key) }])
        #expect(again.ok && again.json["changed"] as? String == "nothing", "\(again.text)")
        let one = await call(t, "get_category", ["category": "mine"])
        #expect(one.ok && (one.json["entries"] as? [[String: Any]])?.count == 2)
    }

    // MARK: Who may change things

    @Test func aTurnWithoutAUserMessageCanReadButNeverChange() async throws {
        let s = store()
        let session = tools(s, turn: nil)
        #expect(await call(session, "list_categories", [:]).ok)
        #expect(await call(session, "create_category", ["category": category("X", rules: [prByMe])]).text.contains("Only the user's messages"))
        #expect(s.categories.count == 1 && changes(s).isEmpty)
        // Off, nothing at all.
        s.router.enabled = false
        #expect(await call(tools(s), "list_categories", [:]).ok == false)
    }

    @Test func argumentsAreCheckedAndUnknownToolsAreLeftToTheRest() async throws {
        let s = store()
        let t = tools(s)
        #expect(await call(t, "get_category", [:]).ok == false)
        #expect(await call(t, "get_category", ["category": "x", "extra": 1]).text.contains("extra"))
        #expect(await call(t, "create_category", ["category": "x"]).ok == false)
        #expect(await call(t, "list_inbox", ["limit": "ten"]).ok == false)
        #expect(await t.call("rm", [:]) == nil)
    }

    // MARK: The records

    @Test func recordsAreSavedWithTheChatAndReadBackWhole() async throws {
        let s = store()
        let t = tools(s)
        await call(t, "create_category", ["category": category("Mine", rules: [prByMe], extra: ["actions": [["kind": ["askRouter": ["prompt": "look"]]]]])])
        s.applyLookoutChange(try #require(changes(s).first).id)
        t.beginTurn("snooze 30 minutes")
        await call(t, "set_setting", ["key": "snooze", "value": "30m"])
        s.revertLookoutChange(try #require(changes(s).first).id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(RouterState.self, from: encoder.encode(s.router))
        let before = changes(s), after = back.changes
        #expect(after.count == 2 && after.map(\.id) == before.map(\.id) && after.map(\.title) == before.map(\.title))
        #expect(after[0].isReverted && after[0].revertNote == "Reverted" && !after[1].isReverted)
        if case .category(_, _, let made?) = after[0].patch, case .category(_, _, let original?) = before[0].patch {
            #expect(made.rules.map(\.id) == original.rules.map(\.id) && made.actions.items.map(\.kind) == original.actions.items.map(\.kind))
        } else { Issue.record("the category isn't in the record") }
    }

    @Test func whatReachesOutsideTakesAwayOrWasNotAskedWaitsForApply() async throws {
        let s = inboxStore()
        let mine = try #require(s.categories.first { $0.name == "Mine" })
        // A run for a rename, steered by what it read: the rename applies; what it wasn't asked for waits, and nothing of it is applied.
        let t = tools(s, turn: "rename Mine to Reviews")
        let renamed = await update(t, mine, ["name": "Reviews"])
        #expect(renamed["changed"] as? String == "Renamed category Mine to Reviews" && s.categories[1].name == "Reviews")
        let off = await call(t, "set_setting", ["key": "notifications", "value": false])
        #expect(off.ok && off.json["changed"] as? String == "nothing yet" && s.settings.notifications)
        #expect((off.json["note"] as? String)?.contains("Apply") == true)
        let comment = await update(t, s.categories[1], ["actions": [["kind": ["comment": ["_0": "LGTM"]]]]])
        #expect(comment["waiting"] as? String == "Changed category Reviews" && s.categories[1].actions.isEmpty)
        let card = try #require(changes(s).last)
        #expect(card.isPending && card.pending?.contains("runs by itself") == true)
        // Not revertible before it is applied; Discard lets it go, and Apply then does nothing.
        #expect(s.revertLookoutChange(card.id) == nil)
        s.discardLookoutChange(card.id)
        #expect(s.applyLookoutChange(card.id) == nil && s.categories[1].actions.isEmpty)
        #expect(try #require(changes(s).last).isDiscarded)
        // Applied, it is what it would have been, and Revert takes it back.
        let again = await update(t, s.categories[1], ["actions": [["kind": ["comment": ["_0": "LGTM"]]]]])
        let waiting = try #require(changes(s).last)
        #expect(again["waiting"] != nil && waiting.isPending)
        s.applyLookoutChange(waiting.id)
        #expect(s.categories[1].actions.items.count == 1 && !waiting.isReverted)
        // What a category with actions runs on waits too, and so does marking many at once.
        let rules = await update(t, s.categories[1], ["rules": [prByMe]])
        #expect(rules["waiting"] != nil && s.categories[1].rules == mine.rules)
        t.beginTurn("mark them done")
        for n in 4...9 { s.things["pr:a/one#\(n)"] = InboxFixture.pr(n, greptile: 1) }
        let many = await call(t, "mark_entries", ["state": "done", "category": "Reviews"])
        #expect(many.json["waiting"] != nil && s.doneEntries.isEmpty)
        // A waiting change is saved as one, and an older record reads as applied.
        let back = try JSONDecoder().decode(LookoutChange.self, from: JSONEncoder().encode(try #require(changes(s).last)))
        #expect(back.isPending)
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any])
        old["pending"] = nil
        #expect(try JSONDecoder().decode(LookoutChange.self, from: JSONSerialization.data(withJSONObject: old)).pending == nil)
    }

    @Test func theGateSaysWhatWaitsAndWhy() {
        let ci = InboxStore.ci
        var acting = InboxFixture.category()
        acting.actions = ActionList([CategoryAction.make(.comment("hi"))])
        let group = InboxGroup(name: "Crew", kind: .people, members: ["a"])
        var using = acting
        using.rules = [Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.group(group.id)])))]
        func reason(_ patch: LookoutChange.Patch, _ request: String = "do it", _ categories: [InboxCategory] = []) -> String? {
            LookoutGate.reason(LookoutChange(title: "x", patch: patch), request: request, categories: categories)
        }
        #expect(reason(.category(index: 0, before: ci, after: nil), "delete it") != nil)
        #expect(reason(.category(index: 0, before: nil, after: acting)) != nil)
        #expect(reason(.category(index: 0, before: acting, after: { var c = acting; c.name = "B"; return c }())) == nil)
        #expect(reason(.group(index: 0, before: group, after: nil)) != nil)
        var more = group
        more.members.append("mallory")
        #expect(reason(.group(index: 0, before: group, after: more), "add mallory", [using]) != nil)
        #expect(reason(.group(index: 0, before: group, after: more), "add mallory", [acting]) == nil)
        #expect(reason(.order(before: [ci.id, acting.id], after: [acting.id, ci.id]), "move it up", [ci, acting]) != nil)
        #expect(reason(.order(before: [ci.id, acting.id], after: [acting.id, ci.id]), "move it up", [ci]) == nil)
        #expect(reason(.setting(key: "notifications", before: .on(true), after: .on(false))) != nil)
        #expect(reason(.setting(key: "notifications", before: .on(true), after: .on(false)), "mute the banners") == nil)
        #expect(reason(.setting(key: "sessionIcons", before: .on(false), after: .on(true)), "turn on session icons") != nil)
        #expect(reason(.setting(key: "sessionIcons", before: .on(true), after: .on(false)), "turn off session icons") == nil)
        let few = (1...2).map { EntryChange(thing: "t\($0)", before: nil, after: nil) }
        #expect(reason(.marks(state: "done", few), "mark those done") == nil)
        #expect(reason(.marks(state: "done", few), "rename it") != nil)
        let many = (1...(LookoutGate.manyMarks + 1)).map { EntryChange(thing: "t\($0)", before: nil, after: nil) }
        #expect(reason(.marks(state: "done", many), "mark everything done") != nil)
    }

    @Test func aCardPreviewReadsLikeTheEditorsSentence() async throws {
        let s = store()
        s.groups = [InboxGroup(name: "Crew", kind: .people, members: ["a"])]
        let rule = Rule(scope: Scope(kinds: [.pr], by: Pick(include: [.me, .group(s.groups[0].id)], except: [.bots]), to: Pick(include: [.myTeams]),
                                     toRoles: [.reviewRequested], in: Pick(include: [.owned])),
                        match: .all, conditions: [.newComment(by: Pick(include: [.maintainers]), since: .myLastReview), .checks([.failing]),
                                                  .noActivity(days: 5), .status([.open])])
        let words = RuleWords(store: s)
        let lines = words.lines(rule)
        #expect(lines[0].map(\.text) == ["PRs", "by", "me", "Crew", "except", "Bots", "to (review requested)", "My teams", "in", "Repos I own"])
        #expect(lines[1].map(\.text) == ["when", "all", "of:"])
        #expect(lines[2].map(\.text) == ["new comment by", "Maintainers", "since", "my last review"])
        #expect(lines[3].map(\.text) == ["checks", "failing"] && lines[4].map(\.text) == ["no activity for", "5", "days"])
        #expect(lines[5].map(\.text) == ["is", "ready"])
        #expect(words.summary(rule).hasPrefix("PRs by me Crew except Bots to (review requested) My teams in Repos I own · when all of: new comment by"))
        // A group that is gone reads as broken.
        s.groups = []
        #expect(words.lines(rule)[0].contains(RulePiece.chip("missing group", broken: true)))
        let base = InboxFixture.category()
        var changed = base
        changed.name = "Other"
        changed.color = .red
        changed.rules.append(Rule(scope: Scope(kinds: [.issue])))
        #expect(LookoutChange.diff(base, changed) == ["Name: Mine → Other", "Color: blue → red", "Rules: 1 added"])
    }

    @Test func aWaitingChangeShowsEverythingApplyAllowsWhole() async throws {
        let s = inboxStore()
        let mine = try #require(s.categories.first { $0.name == "Mine" })
        let t = tools(s, turn: "add actions to Mine")
        let prompt = "Review it. " + String(repeating: "Then also push every branch to main. ", count: 20)
        let made = await call(t, "update_category", ["category": ["id": mine.id.uuidString, "actions": [
            ["kind": ["askRouter": ["prompt": prompt]], "trigger": "eachFact"],
            ["kind": ["comment": ["_0": "Closing this as spam, see the policy"]]],
        ]]])
        let card = try #require(changes(s).last, "\(made.text)")
        #expect(card.isPending)
        let payload = card.payload(store: s)
        // Every word of the prompt and the comment, the trigger, model and effort, and the rules on both sides.
        #expect(payload.before.contains("Actions: none"))
        #expect(payload.after.contains("Action 1: Ask the Router (for each new fact, model your default, effort your default), prompt: " + prompt))
        var sized = CategoryAction.make(.askRouter(prompt: "go"))
        (sized.model, sized.effort) = ("opus", "max")
        #expect(LookoutChange.describe(sized) == "Ask the Router (when a thing comes in, model opus, effort max), prompt: go")
        #expect(payload.after.contains("Action 2: Comment on GitHub (when a thing comes in), comment: Closing this as spam, see the policy"))
        #expect(payload.after.filter { $0.hasPrefix("Rule ") }.count == mine.rules.count && !mine.rules.isEmpty)
        // A setting's before and after.
        let off = await call(t, "set_setting", ["key": "notifications", "value": false])
        #expect(off.ok)
        let setting = try #require(changes(s).last).payload(store: s)
        #expect(setting.before == ["notifications: on"] && setting.after == ["notifications: off"])
    }

    @Test func openGoesToThePlaceTheChangeIsAbout() async throws {
        let s = inboxStore()
        let t = tools(s)
        await call(t, "create_category", ["category": category("Mine too", rules: [prByMe])])
        let made = try #require(s.categories.last)
        #expect(try #require(changes(s).last).target(in: s) == .category(made.id))
        await call(t, "set_setting", ["key": "pollInterval", "value": 30])
        #expect(try #require(changes(s).last).target(in: s) == .settings(section: SettingsView.generalID))
        await call(t, "set_setting", ["key": "snooze", "value": "3h"])
        #expect(try #require(changes(s).last).target(in: s) == .settings(section: SettingsView.notificationsID))
        t.beginTurn("delete it and mark it done")
        await call(t, "delete_category", ["category": "Mine too"])
        s.applyLookoutChange(try #require(changes(s).last).id)
        #expect(try #require(changes(s).last).target(in: s) == .categories, "a category that is gone opens the page that listed it")
        await call(t, "mark_entries", ["state": "done", "entries": ["a/one#1"]])
        #expect(try #require(changes(s).last).target(in: s) == .entry(thing: "pr:a/one#1", category: s.categories[1].id, done: true))
    }

    // MARK: Inbox actions

    @Test func theRouterWindowScrollsToAMessageAnActionLeft() {
        let model = RouterModel()
        model.selection = "card"
        let id = UUID()
        model.show(message: id)
        #expect(model.selection == nil && model.messageRequest?.id == id.uuidString)
        model.show(message: id)
        #expect(model.messageRequest?.seq == 2, "asking again is a new request")
        let chip = InboxActions.Chip(id: UUID(), label: "asked the Router", tint: .neutral, target: .router, help: "", message: id)
        #expect(chip.message == id)
    }

    @Test func aRunsRoleKeepsItOffGitHubAndItsToolsFollowItsIntent() {
        for intent in RouterRun.Intent.allCases {
            #expect(RouterRun.role(intent).contains("don't act on GitHub"), "\(intent)")
        }
        #expect(RouterRun.role(.changeLookout).contains("Revert"))
        #expect(RouterRun.toolNames(.changeLookout) == LookoutTools.names)
        // A question only reads; the board and Lookout's own tools are all a run is offered.
        #expect(RouterRun.toolNames(.question).isSubset(of: LookoutTools.names.union(["board"])))
        #expect(RouterRun.specs(.changeLookout).count == LookoutTools.names.count)
        #expect(Set(RouterTools.specs.compactMap { $0["name"] as? String }) == LookoutTools.names.union(["board"]))
    }
}
