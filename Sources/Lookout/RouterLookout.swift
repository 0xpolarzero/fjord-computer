import Foundation

// The Router's second surface: Lookout itself (its categories, groups, inbox and settings), besides the Claude Code sessions.
// It never touches GitHub. Reads answer from the store; a change applies at once and leaves a record in the history (a card with
// Open and Revert, see LookoutChange).

// MARK: - JSON

enum LookoutJSON {
    static func object<T: Encodable>(_ value: T) -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value), let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return NSNull() }
        return object
    }

    static func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = Shapes.parseDate(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an ISO 8601 date"))
            }
            return date
        }
        do { return try decoder.decode(type, from: data) } catch let error as DecodingError {
            throw RouterTools.Failure(describe(error))
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        switch error {
        case .keyNotFound(let key, let context): return "\(path(context)): missing `\(key.stringValue)`"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(path(context)): \(context.debugDescription)"
        @unknown default: return error.localizedDescription
        }
    }
}

// MARK: - The tools

@MainActor
enum LookoutTools {
    struct Tool {
        let name: String
        let doc: String
        let fields: [JSONShape.Field]
        /// A schema written by hand, for the one tool whose input depends on its key.
        var schema: [String: Any]?
        var reads = false

        var spec: [String: Any] { ["name": name, "description": doc, "inputSchema": schema ?? Shapes.schema(.object(fields))] }
    }

    private static let categoryRef = JSONShape.Field("category", .string("id or name"), "A category's id or name.")
    private static let changeNote = " The change applies at once and the user gets a card in the history with its before and after, an Open button and a Revert button: don't repeat it back."

    static let tools: [Tool] = [
        Tool(name: "list_categories", doc: "Lists Lookout's inbox categories in priority order (a thing is in the first one a rule matches), each with its rules as JSON (the form create_category and update_category take), a plain-words summary of each rule, its actions and how many open and unread things it holds. Also says how many things are done.", fields: [], reads: true),
        Tool(name: "get_category", doc: "One category as JSON (the form update_category takes), with its rules in plain words and its open things.", fields: [categoryRef], reads: true),
        Tool(name: "create_category", doc: "Creates an inbox category: a named, coloured list of the PRs, issues and workflows that need the user, by rules. It goes last (or at `at`, 0 is first); a thing is in the first category that matches. Rejected, with every reason as the editor shows it, if a rule can never match. Actions run by themselves for things that come in: add one only when the user asked, and never a GitHub comment on your own.\(changeNote)\n\n\(LookoutDocs.ruleGrammar)",
             fields: [.init("category", .named("Category"), "The category."), .init("at", .int, "Position, 0 is first. Left out: last.", fallback: .absent)]),
        Tool(name: "update_category", doc: "Changes a category. Give its `id` and the fields that change (name, symbol, color, rules, notifies, hidden, actions); fields left out keep their value, and `rules` or `actions`, when given, replace the whole list (keep each rule's `id` from get_category so its history stays). The same JSON and the same refusals as create_category.\(changeNote)",
             fields: [.init("category", .named("Category"), "The category's `id` and what changes.")]),
        Tool(name: "delete_category", doc: "Deletes a category: its things go to the next category that matches. The CI category can't be deleted (hide it with update_category).\(changeNote)", fields: [categoryRef]),
        Tool(name: "reorder_categories", doc: "Sets the order of the categories, which is their priority. Name every category, in the new order.\(changeNote)",
             fields: [.init("order", .list(.string("id or name")), "Every category's id or name, first to last.")]),
        Tool(name: "list_groups", doc: "Lists the groups (named lists of people or repos usable as one value in any rule) with their members and the categories that use them.", fields: [], reads: true),
        Tool(name: "create_group", doc: "Creates a group of people (GitHub logins) or repos (`owner/repo`, `owner/*`). Use its id in rules as {\"group\":{\"_0\":\"<id>\"}}.\(changeNote)",
             fields: [.init("group", .named("Group"), "The group.")]),
        Tool(name: "update_group", doc: "Changes a group (its `id`, and what changes; `members`, when given, replaces the list). Rules using it follow. The kind can't change while rules use it.\(changeNote)",
             fields: [.init("group", .named("Group"), "The group's `id` and what changes.")]),
        Tool(name: "delete_group", doc: "Deletes a group no rule uses.\(changeNote)", fields: [.init("group", .string("id or name"), "A group's id or name.")]),
        Tool(name: "list_inbox", doc: "Lists things in the inbox: id, title, repo#number, kind, category, the facts that put it there (\"2 unresolved\", \"last comment: @x\"), whether it is done or unread, author, last update and URL. Open ones by default, newest first.",
             fields: [.init("category", .string("id or name"), "Only this category.", fallback: .absent),
                      .init("query", .string("words"), "Words that all appear in the title, repo, number, author, category or facts.", fallback: .absent),
                      .init("state", .choice(["open", "done", "all"]), "Default open.", fallback: .absent),
                      .init("limit", .int, "At most this many (default 50, at most 200).", fallback: .absent)], reads: true),
        Tool(name: "explain_entry", doc: "Says why a thing is where it is: the category and rules that matched it and the facts, the other categories it would match but comes after, rules that are off until fixed, and the thing's own state (status, author, labels, checks…) for working out why it isn't somewhere.",
             fields: [.init("entry", .string("thing id, owner/repo#n, or title words"), "The thing: its id from list_inbox, `owner/repo#12`, or words of its title.")], reads: true),
        Tool(name: "mark_entries", doc: "Marks things done (acknowledges their current facts; they come back only on a new fact), seen, or puts done ones back. Give `entries` or a whole `category` (its open ones for done, its unread for seen, its done ones for restore). At most 100.\(changeNote)",
             fields: [.init("state", .choice(["done", "seen", "unread", "restore"]), "What to mark."),
                      .init("entries", .list(.string("thing id, owner/repo#n, or title words")), "Things.", fallback: .absent),
                      .init("category", .string("id or name"), "Every matching thing of this category.", fallback: .absent)]),
        Tool(name: "get_settings", doc: "Lists the settings the Router may change, with their values and what they take. The GitHub token, the account, quitting and the Router's own switch are not among them.", fields: [], reads: true),
        Tool(name: "set_setting", doc: "Changes one setting (get_settings lists the keys and what each takes).\(changeNote)", fields: [],
             schema: ["type": "object", "additionalProperties": false, "required": ["key", "value"],
                      "properties": [
                          "key": ["type": "string", "enum": LookoutSetting.all.map(\.key)],
                          "value": ["description": LookoutSetting.all.map { s in
                              "\(s.key): " + (String(data: (try? JSONSerialization.data(withJSONObject: s.schema, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? "")
                          }.joined(separator: "; ")],
                      ]] as [String: Any]),
        Tool(name: "list_known", doc: "The repos, people or teams Lookout knows (from what it has fetched and what the user has), to fill a rule's values; also the special values and the groups of that kind.",
             fields: [.init("kind", .choice(["repos", "people", "teams"]), "What to list."),
                      .init("query", .string("text"), "Only those containing it.", fallback: .absent),
                      .init("limit", .int, "At most this many (default 30, at most 100).", fallback: .absent)], reads: true),
    ]

    static let specs: [[String: Any]] = tools.map(\.spec)
    static let names: Set<String> = Set(tools.map(\.name))

    /// A tool's input as a shape: what the Router sends is checked against it, and its schema is made from it.
    static func shape(of name: String) -> JSONShape? { tools.first { $0.name == name }.map { .object($0.fields) } }
}

// MARK: - Running them

extension RouterTools {
    func lookout(_ name: String, _ args: [String: Any], store: Store, ticket: Ticket) async -> RouterRPC.ToolResult? {
        guard LookoutTools.names.contains(name) else { return nil }
        do {
            let reads = LookoutTools.tools.first { $0.name == name }?.reads == true
            try live(ticket, acting: !reads)
            // What a tool does to the categories and groups is the Router's, in this run, in the log.
            let source = store.inboxSource
            store.inboxSource = .routerTool(decision: decision)
            defer { store.inboxSource = source }
            let text: String
            switch name {
            case "list_categories": text = try listCategories(store, args)
            case "get_category": text = try getCategory(store, args)
            case "create_category": text = try saveCategory(store, args, creating: true)
            case "update_category": text = try saveCategory(store, args, creating: false)
            case "delete_category": text = try deleteCategory(store, args)
            case "reorder_categories": text = try reorderCategories(store, args)
            case "list_groups": text = try listGroups(store, args)
            case "create_group": text = try saveGroup(store, args, creating: true)
            case "update_group": text = try saveGroup(store, args, creating: false)
            case "delete_group": text = try deleteGroup(store, args)
            case "list_inbox": text = try listInbox(store, args)
            case "explain_entry": text = try explainEntry(store, args)
            case "mark_entries": text = try markEntries(store, args)
            case "get_settings": text = try getSettings(store, args)
            case "set_setting": text = try setSetting(store, args)
            case "list_known": text = try listKnown(store, args)
            default: return nil
            }
            return RouterRPC.ToolResult(text: text)
        } catch let error as ShapeError {
            return .error("Not changed: " + (error.errorDescription ?? "invalid input"))
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: Helpers

    /// What the Router sent, checked against the tool's own schema (unknown fields, wrong types, missing parts), with the
    /// left-out fields filled in.
    private func checked(_ name: String, _ args: [String: Any]) throws -> [String: Any] {
        guard let shape = LookoutTools.shape(of: name) else { return args }
        return (try Shapes.normalize(args, as: shape)) as? [String: Any] ?? args
    }

    private func category(_ store: Store, _ query: String) throws -> InboxCategory {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: q), let c = store.categories.first(where: { $0.id == id }) { return c }
        let named = store.categories.filter { $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(q) == .orderedSame }
        if named.count == 1 { return named[0] }
        let all = store.categories.map { "“\($0.title)”" }.joined(separator: ", ")
        throw Failure(named.isEmpty ? "No category “\(q)”. Categories: \(all)" : "More than one category is called “\(q)”; use its id")
    }

    private func group(_ store: Store, _ query: String) throws -> InboxGroup {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: q), let g = store.groups.first(where: { $0.id == id }) { return g }
        let named = store.groups.filter { $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(q) == .orderedSame }
        if named.count == 1 { return named[0] }
        throw Failure(named.isEmpty ? "No group “\(q)”. Groups: " + (store.groups.isEmpty ? "none" : store.groups.map { "“\($0.name)”" }.joined(separator: ", "))
                                    : "More than one group is called “\(q)”; use its id")
    }

    private func reference(_ t: Thing) -> String {
        switch t.kind {
        case .workflow: "\(t.repo) \(t.workflowName ?? "workflow")\(t.branch.map { "@\($0)" } ?? "")"
        default: "\(t.repo)#\(t.number ?? 0)"
        }
    }

    private func stamp(_ date: Date) -> String { Shapes.formatDate(date) }

    private func categoryJSON(_ store: Store, _ c: InboxCategory, counts: Bool = true) -> [String: Any] {
        var object = LookoutJSON.object(c) as? [String: Any] ?? [:]
        let words = RuleWords(store: store)
        object["summary"] = c.rules.map(words.summary)
        if counts {
            let open = store.entries(in: c.id)
            object["open"] = open.count
            object["unread"] = open.filter(\.isUnread).count
        }
        return object
    }

    private func entryJSON(_ store: Store, _ e: InboxEntry) -> [String: Any] {
        var out: [String: Any] = [
            "thing": e.id, "ref": reference(e.thing), "kind": e.thing.kind.rawValue, "title": e.thing.title,
            "category": store.categories.first { $0.id == e.categoryID }?.title ?? "", "categoryId": e.categoryID.uuidString,
            "facts": e.facts.map(\.label), "done": e.isDone, "unread": e.isUnread, "updated": stamp(e.thing.updatedAt),
            "url": e.thing.url.absoluteString,
        ]
        if let author = e.thing.author?.login { out["author"] = author }
        return out
    }

    /// A thing by id, `owner/repo#n`, or words of its title.
    private func findEntry(_ store: Store, _ query: String) throws -> InboxEntry? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = store.entries
        if let hit = entries.first(where: { $0.id == q }) { return hit }
        let lower = q.lowercased()
        if let hit = entries.first(where: { reference($0.thing).lowercased() == lower }) { return hit }
        let words = lower.split(separator: " ")
        let found = entries.filter { e in
            let text = "\(e.thing.title) \(reference(e.thing))".lowercased()
            return !words.isEmpty && words.allSatisfy { text.contains($0) }
        }
        if found.count == 1 { return found[0] }
        if found.isEmpty { return nil }
        throw Failure("“\(q)” fits \(found.count) things: " + found.prefix(5).map { "\(reference($0.thing)) \($0.thing.title)" }.joined(separator: "; ") + ". Use a thing id from list_inbox.")
    }

    /// The record of a change, for the card. A change to what an earlier change of this turn touched joins that one's
    /// record (one card, one `changed` in the decision); nil when the two together change nothing, and none is kept.
    @discardableResult
    private func record(_ store: Store, _ change: LookoutChange) -> LookoutChange? {
        var state = store.router
        for id in turnChanges.reversed() {
            guard let i = state.changes.firstIndex(where: { $0.id == id }), !state.changes[i].isReverted else { continue }
            switch state.changes[i].coalesced(with: change) {
            case .separate:
                continue
            case .cancelled:
                state.changes.remove(at: i)
                turnChanges.removeAll { $0 == id }
                store.router = state
                store.dropChange(id)
                return nil
            case .merged(let merged):
                let was = state.changes[i].title
                state.changes[i] = merged
                store.router = state
                store.retitleChange(merged.id, from: was, to: merged.title)
                return merged
            }
        }
        state.changes.append(change)
        RouterFeed.prune(&state)
        store.router = state
        turnChanges.append(change.id)
        store.logChange(change, into: decision)
        return change
    }

    private func done(_ store: Store, _ change: LookoutChange?, _ extra: [String: Any] = [:]) -> String {
        var out = extra
        guard let change else {
            out["changed"] = "nothing"
            out["note"] = "That put back what an earlier change of this turn had changed, so nothing is left to revert."
            return Self.json(out)
        }
        out["changed"] = change.title
        out["changeId"] = change.id.uuidString
        out["note"] = "Applied. The user has a card with Open and Revert."
        return Self.json(out)
    }

    // MARK: Categories

    func listCategories(_ store: Store, _ args: [String: Any]) throws -> String {
        _ = try checked("list_categories", args)
        return Self.json(["categories": store.categories.map { categoryJSON(store, $0) }, "done": store.doneEntries.count])
    }

    func getCategory(_ store: Store, _ args: [String: Any]) throws -> String {
        let args = try checked("get_category", args)
        let c = try category(store, Self.string(args, "category"))
        var object = categoryJSON(store, c)
        object["entries"] = store.entries(in: c.id).prefix(30).map { entryJSON(store, $0) }
        return Self.json(object)
    }

    func saveCategory(_ store: Store, _ args: [String: Any], creating: Bool) throws -> String {
        let tool = creating ? "create_category" : "update_category"
        guard var given = args["category"] as? [String: Any] else { throw Failure("`category` must be an object") }
        // A rule was once about one `kind`: said that way, it is the set of that one.
        if var rules = given["rules"] as? [[String: Any]] {
            for i in rules.indices {
                guard var scope = rules[i]["scope"] as? [String: Any], let kind = scope["kind"], scope["kinds"] == nil else { continue }
                scope["kinds"] = [kind]
                scope["kind"] = nil
                rules[i]["scope"] = scope
            }
            given["rules"] = rules
        }
        var old: InboxCategory?
        if !creating {
            guard let id = given["id"] as? String, UUID(uuidString: id) != nil else { throw Failure("`category.id` is needed: the id from list_categories") }
            guard let found = store.categories.first(where: { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }) else {
                throw Failure("No category with id \(id); call list_categories")
            }
            old = found
            // What isn't given keeps its value; a rule that comes back by its id keeps its date.
            var merged = LookoutJSON.object(found) as? [String: Any] ?? [:]
            for (key, value) in given { merged[key] = value }
            if var rules = given["rules"] as? [[String: Any]] {
                for i in rules.indices where rules[i]["createdAt"] == nil {
                    if let id = rules[i]["id"] as? String, let was = found.rules.first(where: { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }) {
                        rules[i]["createdAt"] = stamp(was.createdAt)
                    }
                }
                merged["rules"] = rules
            }
            given = merged
        } else if given["id"] != nil {
            given["id"] = nil
        }
        var input: [String: Any] = ["category": given]
        if let at = args["at"] { input["at"] = at }
        let checkedInput = try checked(tool, input)
        guard var json = checkedInput["category"] as? [String: Any] else { throw Failure("`category` must be an object") }
        // Only PRs have review requests: a rule without them that didn't say which roles `to` covers doesn't get that one.
        if var rules = json["rules"] as? [[String: Any]] {
            for i in rules.indices {
                guard var scope = rules[i]["scope"] as? [String: Any], let kinds = scope["kinds"] as? [String],
                      !kinds.contains(ThingKind.pr.rawValue), var roles = scope["toRoles"] as? [String] else { continue }
                let said = ((given["rules"] as? [[String: Any]])?[safe: i]?["scope"] as? [String: Any])?["toRoles"] != nil
                if !said || scope["to"] == nil { roles.removeAll { $0 == ToRole.reviewRequested.rawValue }; scope["toRoles"] = roles; rules[i]["scope"] = scope }
            }
            json["rules"] = rules
        }
        var c = try LookoutJSON.decode(InboxCategory.self, from: json)
        c.name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasons = LookoutValidate.category(c, old: old, in: store)
        guard reasons.isEmpty else { throw Failure("Not saved:\n- " + reasons.joined(separator: "\n- ")) }
        var warnings: [String] = []
        if c.rules.isEmpty { warnings.append("It has no rules, so nothing will be in it.") }
        var notes: [String: Any] = warnings.isEmpty ? [:] : ["warnings": warnings]
        let change: LookoutChange
        if let old {
            guard let index = store.categories.firstIndex(where: { $0.id == old.id }) else { throw Failure("The category is gone") }
            guard c != old else { return Self.json(["changed": "nothing", "note": "It already is that."]) }
            store.categories[index] = c
            change = LookoutChange(title: LookoutChange.title(forCategory: old, c), patch: .category(index: index, before: old, after: c))
        } else {
            let at = min(max((checkedInput["at"] as? Int) ?? store.categories.count, 0), store.categories.count)
            store.categories.insert(c, at: at)
            change = LookoutChange(title: LookoutChange.title(forCategory: nil, c), patch: .category(index: at, before: nil, after: c))
        }
        store.categoriesChangedByRouter()
        let recorded = record(store, change)
        notes["category"] = categoryJSON(store, c)
        return done(store, recorded, notes)
    }

    func deleteCategory(_ store: Store, _ args: [String: Any]) throws -> String {
        let c = try category(store, Self.string(try checked("delete_category", args), "category"))
        guard let index = store.categories.firstIndex(where: { $0.id == c.id }) else { throw Failure("The category is gone") }
        store.categories.remove(at: index)
        store.categoriesChangedByRouter()
        return done(store, record(store, LookoutChange(title: LookoutChange.title(forCategory: c, nil), patch: .category(index: index, before: c, after: nil))))
    }

    func reorderCategories(_ store: Store, _ args: [String: Any]) throws -> String {
        let order = try Self.strings(try checked("reorder_categories", args), "order")
        let wanted = try order.map { try category(store, $0).id }
        guard Set(wanted).count == wanted.count else { throw Failure("A category is named twice") }
        let missing = store.categories.filter { !wanted.contains($0.id) }
        guard missing.isEmpty else {
            throw Failure("Name every category: these are missing: " + missing.map { "“\($0.title)”" }.joined(separator: ", "))
        }
        let before = store.categories.map(\.id)
        guard before != wanted else { return Self.json(["changed": "nothing", "note": "They already are in that order."]) }
        store.categories = Store.ordered(store.categories, by: wanted)
        store.categoriesChangedByRouter()
        return done(store, record(store, LookoutChange(title: "Reordered categories", patch: .order(before: before, after: wanted))),
                    ["order": store.categories.map(\.title)])
    }

    // MARK: Groups

    private func groupJSON(_ store: Store, _ g: InboxGroup) -> [String: Any] {
        var object = LookoutJSON.object(g) as? [String: Any] ?? [:]
        object["usedBy"] = LookoutValidate.users(of: g.id, in: store)
        return object
    }

    func listGroups(_ store: Store, _ args: [String: Any]) throws -> String {
        _ = try checked("list_groups", args)
        return Self.json(["groups": store.groups.map { groupJSON(store, $0) }])
    }

    func saveGroup(_ store: Store, _ args: [String: Any], creating: Bool) throws -> String {
        let tool = creating ? "create_group" : "update_group"
        guard var given = args["group"] as? [String: Any] else { throw Failure("`group` must be an object") }
        var old: InboxGroup?
        if creating {
            given["id"] = nil
        } else {
            guard let id = given["id"] as? String, UUID(uuidString: id) != nil else { throw Failure("`group.id` is needed: the id from list_groups") }
            guard let found = store.groups.first(where: { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }) else {
                throw Failure("No group with id \(id); call list_groups")
            }
            old = found
            var merged = LookoutJSON.object(found) as? [String: Any] ?? [:]
            for (key, value) in given { merged[key] = value }
            given = merged
        }
        let checkedInput = try checked(tool, ["group": given])
        var g = try LookoutJSON.decode(InboxGroup.self, from: checkedInput["group"] as Any)
        g.name = g.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        g.members = g.members.map { $0.trimmingCharacters(in: .whitespaces) }.map { g.kind == .people && $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
            .filter { seen.insert($0.lowercased()).inserted }
        let reasons = LookoutValidate.group(g, old: old, in: store)
        guard reasons.isEmpty else { throw Failure("Not saved:\n- " + reasons.joined(separator: "\n- ")) }
        let change: LookoutChange
        if let old {
            guard let index = store.groups.firstIndex(where: { $0.id == old.id }) else { throw Failure("The group is gone") }
            guard g != old else { return Self.json(["changed": "nothing", "note": "It already is that."]) }
            store.groups[index] = g
            change = LookoutChange(title: LookoutChange.title(forGroup: old, g), patch: .group(index: index, before: old, after: g))
        } else {
            store.groups.append(g)
            change = LookoutChange(title: LookoutChange.title(forGroup: nil, g), patch: .group(index: store.groups.count - 1, before: nil, after: g))
        }
        store.categoriesChangedByRouter()
        let recorded = record(store, change)
        return done(store, recorded, ["group": groupJSON(store, g)])
    }

    func deleteGroup(_ store: Store, _ args: [String: Any]) throws -> String {
        let g = try group(store, Self.string(try checked("delete_group", args), "group"))
        let users = LookoutValidate.users(of: g.id, in: store)
        guard users.isEmpty else { throw Failure("“\(g.name)” is used by \(users.joined(separator: ", ")): take it out of their rules first") }
        guard let index = store.groups.firstIndex(where: { $0.id == g.id }) else { throw Failure("The group is gone") }
        store.groups.remove(at: index)
        store.categoriesChangedByRouter()
        return done(store, record(store, LookoutChange(title: LookoutChange.title(forGroup: g, nil), patch: .group(index: index, before: g, after: nil))))
    }

    // MARK: Inbox

    func listInbox(_ store: Store, _ args: [String: Any]) throws -> String {
        let args = try checked("list_inbox", args)
        let state = args["state"] as? String ?? "open"
        let limit = min(max((args["limit"] as? Int) ?? 50, 1), 200)
        let c = try (args["category"] as? String).map { try category(store, $0) }
        let query = (args["query"] as? String) ?? ""
        var rows = store.inboxRows(.done, search: query)
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            rows = store.entries.sorted { ($0.isDone ? 1 : 0, $1.thing.updatedAt) < ($1.isDone ? 1 : 0, $0.thing.updatedAt) }
        }
        rows = rows.filter { e in
            (c == nil || e.categoryID == c!.id) && (state == "all" || (state == "done") == e.isDone)
        }
        return Self.json(["count": rows.count, "entries": rows.prefix(limit).map { entryJSON(store, $0) }])
    }

    func explainEntry(_ store: Store, _ args: [String: Any]) throws -> String {
        let args = try checked("explain_entry", args)
        let query = try Self.string(args, "entry")
        let entry = try findEntry(store, query)
        let thing = entry?.thing ?? store.things.values.first { $0.id == query || reference($0).lowercased() == query.lowercased() }
        guard let thing else { throw Failure("No thing like “\(query)” is known; list_inbox lists what is") }
        let context = store.inboxContext
        let words = RuleWords(store: store)
        var home: [String: Any]?
        var also: [[String: Any]] = []
        var off: [[String: Any]] = []
        for category in store.categories {
            var matched: [[String: Any]] = []
            for (i, rule) in category.rules.enumerated() {
                let problems = InboxEngine.problems(rule)
                if !problems.isEmpty {
                    off.append(["category": category.title, "rule": i, "summary": words.summary(rule), "reasons": problems.map(\.reason)])
                    continue
                }
                guard let facts = InboxEngine.facts(rule, thing, marks: store.marks[thing.id], context: context) else { continue }
                matched.append(["rule": i, "summary": words.summary(rule), "facts": facts.map(\.label)])
            }
            guard !matched.isEmpty else { continue }
            let hit: [String: Any] = ["category": category.title, "categoryId": category.id.uuidString, "rules": matched]
            if home == nil { home = hit } else { also.append(hit) }
        }
        var inbox = "not in the inbox: no rule of any category matches it"
        if let entry {
            let name = store.categories.first { $0.id == entry.categoryID }?.title ?? ""
            inbox = "in “\(name)”" + (entry.isDone ? ", done" : entry.isUnread ? ", unread" : "")
        }
        var out: [String: Any] = [
            "thing": thing.id, "ref": reference(thing), "title": thing.title, "kind": thing.kind.rawValue, "inbox": inbox,
            "status": thing.status.rawValue, "labels": thing.labels, "assignees": thing.assignees,
            "requestedReviewers": thing.requestedReviewers, "hasConflicts": thing.hasConflicts,
        ]
        if let author = thing.author { out["author"] = author.login + (author.isBot ? " (bot)" : "") + ", " + author.association.rawValue }
        if let checks = thing.checks { out["checks"] = checks.rawValue }
        if let home { out["matched"] = home }
        if !also.isEmpty { out["alsoMatchesButComesAfter"] = also }
        if !off.isEmpty { out["rulesOffUntilFixed"] = off }
        return Self.json(out)
    }

    func markEntries(_ store: Store, _ args: [String: Any]) throws -> String {
        let args = try checked("mark_entries", args)
        let state = try Self.string(args, "state")
        let refs = try Self.strings(args, "entries")
        let c = try (args["category"] as? String).map { try category(store, $0) }
        guard !refs.isEmpty || c != nil else { throw Failure("Give `entries` or a `category`") }
        var targets: [InboxEntry] = []
        for ref in refs {
            guard let hit = try findEntry(store, ref) else { throw Failure("No thing in the inbox like “\(ref)”; list_inbox lists what is") }
            targets.append(hit)
        }
        if let c {
            targets += store.entries.filter { $0.categoryID == c.id && !targets.contains($0) }
        }
        let wanted: [InboxEntry] = targets.filter {
            switch state {
            case "done": !$0.isDone
            case "seen": $0.isUnread
            case "unread": !$0.isUnread && !$0.isDone
            default: $0.isDone
            }
        }
        guard !wanted.isEmpty else { return Self.json(["changed": "nothing", "note": "Nothing to mark: those are already \(state == "restore" ? "open" : state)."]) }
        guard wanted.count <= 100 else { throw Failure("That is \(wanted.count) things; at most 100 at a time") }
        var changes: [EntryChange] = []
        for e in wanted {
            let before = store.marks[e.id]
            switch state {
            case "done": store.markDone(e)
            case "seen": store.markSeen(e)
            case "unread": store.markUnread(e)
            default: store.restore(e)
            }
            changes.append(EntryChange(thing: e.id, before: before, after: store.marks[e.id]))
        }
        let n = changes.count
        let title = state == "restore" ? "Restored \(n)" : "Marked \(n) \(state)"
        return done(store, record(store, LookoutChange(title: title, patch: .marks(state: state, changes))),
                    ["things": wanted.prefix(10).map { reference($0.thing) }])
    }

    // MARK: Settings

    func getSettings(_ store: Store, _ args: [String: Any]) throws -> String {
        _ = try checked("get_settings", args)
        let rows = LookoutSetting.all.map { s -> [String: Any] in
            let value = s.read(store)
            var shown: Any = s.display(value)
            if case .on(let on) = value { shown = on } else if case .number(let n) = value { shown = Int(n) }
            return ["key": s.key, "value": shown, "description": s.doc, "takes": s.schema]
        }
        return Self.json(["settings": rows])
    }

    func setSetting(_ store: Store, _ args: [String: Any]) throws -> String {
        guard let key = args["key"] as? String, let setting = LookoutSetting.named(key) else {
            throw Failure("`key` must be one of " + LookoutSetting.all.map(\.key).joined(separator: ", "))
        }
        guard args.keys.allSatisfy({ ["key", "value"].contains($0) }), let raw = args["value"] else { throw Failure("Give `key` and `value`") }
        let after: SettingValue
        do { after = try setting.parse(raw, Date()) } catch { throw Failure("`value` for \(key) \(error.localizedDescription)") }
        let before = setting.read(store)
        guard before != after else { return Self.json(["changed": "nothing", "note": "\(key) already is \(setting.display(after))."]) }
        do { try setting.apply(store, after) } catch { throw Failure("Couldn't change \(key): \(error.localizedDescription)") }
        let now = setting.read(store)
        let change = LookoutChange(title: setting.title(after: now, word: raw as? String), patch: .setting(key: key, before: before, after: now))
        return done(store, record(store, change), ["setting": key, "value": setting.display(now)])
    }

    // MARK: Known values

    func listKnown(_ store: Store, _ args: [String: Any]) throws -> String {
        let args = try checked("list_known", args)
        let kind = try Self.string(args, "kind")
        let query = ((args["query"] as? String) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let limit = min(max((args["limit"] as? Int) ?? 30, 1), 100)
        let data = EditorData(store: store)
        let all: [String]
        var special: [String]
        let groupKind: InboxGroup.Kind
        switch kind {
        case "repos": all = data.repoNames(); special = ["owned", "contributed", "involved (PRs and issues)"]; groupKind = .repos
        case "people": all = data.logins(); special = ["me", "maintainers", "bots"]; groupKind = .people
        default: all = data.teams(); special = ["myTeams"]; groupKind = .people
        }
        if kind == "teams" { special = special + ["(a team is {\"team\":{\"_0\":\"org/team\"}}; only in a PR rule's `to` with reviewRequested)"] }
        let values = all.filter { query.isEmpty || $0.lowercased().contains(query) }
        return Self.json(["kind": kind, "values": Array(values.prefix(limit)), "total": values.count, "special": special,
                          "groups": kind == "teams" ? [] : store.groups.filter { $0.kind == groupKind }.map { ["id": $0.id.uuidString, "name": $0.name] }])
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
