import Foundation

// What the Router is told about Triage's own data: one description of each value (categories, rules, conditions,
// groups) from which the tools' JSON schemas, the grammar written in their descriptions, the examples, the defaults
// filled in and the check of what the Router sends are all made. A change to the model that this does not follow fails
// a test (see RouterFjordTests, its schemas), so the Router is never told something the model doesn't take.
//
// The JSON is the model's own Codable form (enums with a payload are `{"case": {…}}`), so what `get_category` shows is what
// `update_category` takes back.

/// How a value is written.
indirect enum JSONShape {
    case string(String = "text")
    case uuid
    case date
    case int
    case bool
    /// One of these words.
    case choice([String])
    case list(JSONShape)
    /// A set of those words, written as a list.
    case choices([String])
    case object([Field])
    /// An enum case: an object with the one key that names it.
    case tagged([Variant])
    /// A shape defined once, by name (`Shapes.named`).
    case named(String)

    struct Field {
        var name: String
        var shape: JSONShape
        var doc: String
        /// Left out: this is filled in (and the schema doesn't require it). Nil: required.
        var fallback: Fallback?

        init(_ name: String, _ shape: JSONShape, _ doc: String = "", fallback: Fallback? = nil) {
            self.name = name
            self.shape = shape
            self.doc = doc
            self.fallback = fallback
        }
    }

    enum Fallback {
        case value(Any)
        /// Optional with no value: the key may simply be left out.
        case absent
        case newUUID
        case now
    }

    struct Variant {
        var tag: String
        /// The case's payload; nil is a case with none (written `{}`).
        var body: JSONShape?
        var doc: String

        init(_ tag: String, _ body: JSONShape? = nil, _ doc: String) {
            self.tag = tag
            self.body = body
            self.doc = doc
        }
    }
}

/// A fault in what the Router sent, with where.
struct ShapeError: LocalizedError {
    var path: String
    var message: String
    var errorDescription: String? { path.isEmpty ? message : "\(path): \(message)" }
}

enum Shapes {
    // MARK: The definitions

    static func people() -> JSONShape { .named("People") }
    static func repos() -> JSONShape { .named("Repos") }

    private static func pick(_ value: JSONShape) -> JSONShape {
        .object([
            .init("include", .list(value), "Any of these. Empty: anyone/anywhere (only useful with `except`).", fallback: .value([Any]())),
            .init("except", .list(value), "Never these.", fallback: .value([Any]())),
        ])
    }

    private static let since = JSONShape.choice(Since.allCases.map(\.rawValue))
    private static let sinceField = JSONShape.Field("since", since,
        "Count events after: `done` (you last marked the thing done, or the rule was made; the default), `myLastReview` (PRs: your latest review; with none nothing matches) or `myLastComment` (your latest comment; with none, since the thing was opened).",
        fallback: .value(Since.done.rawValue))

    private static func by(_ what: String) -> JSONShape.Field { .init("by", people(), what, fallback: .value(["include": [Any](), "except": [Any]()])) }

    /// The shapes with a name: used more than once, or recursive in the docs.
    static let definitions: [String: JSONShape] = [
        "People": pick(.named("Person")),
        "Repos": pick(.named("Repo")),
        "Labels": pick(.string("label")),
        "Person": .tagged([
            .init("me", nil, "You."),
            .init("user", .object([.init("_0", .string("login"), "A GitHub login, without @. Greptile is `greptile-apps[bot]`.")]), "A person or bot."),
            .init("group", .object([.init("_0", .uuid, "A people group's id (list_groups).")]), "A people group."),
            .init("maintainers", nil, "People with owner, member or collaborator rights on the thing's repo."),
            .init("bots", nil, "Accounts GitHub marks as bots."),
            .init("team", .object([.init("_0", .string("org/team"), "`org/team`.")]), "A team asked to review. Only in a PR rule's `to`, with `reviewRequested`."),
            .init("myTeams", nil, "Every team you are in. Only in a PR rule's `to`, with `reviewRequested`."),
        ]),
        "Repo": .tagged([
            .init("repo", .object([.init("_0", .string("owner/repo"), "`owner/repo`.")]), "One repo."),
            .init("owner", .object([.init("_0", .string("owner"), "An owner (user or org).")]), "Every repo of an owner (`owner/*`)."),
            .init("group", .object([.init("_0", .uuid, "A repo group's id (list_groups).")]), "A repo group."),
            .init("owned", nil, "Repos you own."),
            .init("contributed", nil, "Repos with a merged or open PR of yours."),
            .init("involved", nil, "PRs and issues only: anywhere you are the author, assignee or requested reviewer, were mentioned, or commented."),
        ]),
        "Condition": .tagged([
            .init("newComment", .object([by("Who wrote it."), sinceField]), "A new comment by."),
            .init("newReview", .object([by("Who reviewed."), sinceField]), "PRs: a new review by."),
            .init("newCommits", .object([by("Who pushed."), sinceField]), "PRs: new commits by."),
            .init("mentions", .object([.init("_0", people(), "Who is mentioned.", fallback: .value(["include": [Any](), "except": [Any]()])), sinceField]),
                  "Someone is @-mentioned."),
            .init("lastComment", .object([by("Who wrote the latest conversation comment (reviews with text count, inline threads don't).")]),
                  "The latest comment is by."),
            .init("unresolvedThreads", .object([
                .init("startedBy", people(), "Only threads started by.", fallback: .absent),
                .init("lastReplyBy", people(), "Only threads last replied to by.", fallback: .absent),
            ]), "PRs: open review threads."),
            .init("approved", .object([by("Who approved (each reviewer's latest review).")]), "PRs: approved by."),
            .init("changesRequested", .object([by("Who asked for changes (each reviewer's latest review).")]), "PRs: changes requested by."),
            .init("checks", .object([.init("_0", .choices(CheckState.allCases.map(\.rawValue)), "Any of these states.")]), "PRs: the checks are."),
            .init("hasConflicts", nil, "PRs: has merge conflicts."),
            .init("behindBase", nil, "PRs: the base branch has moved on (GitHub only says so when branch protection requires up-to-date branches)."),
            .init("status", .object([.init("_0", .choices(ThingStatus.allCases.map(\.rawValue)),
                                          "Any of these. `open` means ready for review. Issues are only `open` or `closed`.")]), "PRs and issues: the status is."),
            .init("labeled", .object([.init("_0", .named("Labels"), "Label names.")]), "Has a label."),
            .init("noActivity", .object([.init("days", .int, "Days, at least 1.")]), "Nothing happened for N days."),
            .init("greptileBelow", .object([.init("_0", .int, "1 to 5.")]), "PRs: Greptile's score is below N."),
            .init("commentLabel", .object([.init("_0", .choices(CommentLabel.allCases.map(\.rawValue)),
                                                 "Any of these labels: `asks` (a question or decision for you), `todo` (a change or action from you: rebase, fix, address a review), `fyi` (nothing to do), `noise` (thanks, +1, bot chatter).")]),
                  "PRs and issues: Jev labeled a new comment, review or thread reply (not yours) so; `asks` and `todo` only after your latest word there. Needs a TypeSafe key; without one it never matches."),
            .init("noise", .object([.init("_0", .bool, "`true`: noise (bots, and what Jev labels noise); `false`: from a person.")]),
                  "PRs and issues: a new comment (not yours) is noise, or from a person. What it matches as noise never shows a banner."),
            .init("importance", .object([.init("_0", .choice(Importance.allCases.map(\.rawValue)), "At least this level.")]),
                  "PRs and issues: Jev rates the review request to you (or a team of yours), or your assignment, at least this important. Needs a TypeSafe key."),
            .init("workflow", .object([.init("_0", .choices(CheckState.allCases.map(\.rawValue)), "Any of these states (`pending` is running).")]),
                  "Workflows: the latest run is."),
        ]),
        "Scope": .object([
            .init("kinds", .choices(ThingKind.allCases.map(\.rawValue)), "What the rule is about, at least one: `pr` and `issue` together or alone, or `workflow` alone."),
            .init("by", people(), "PRs and issues: the author.", fallback: .absent),
            .init("to", people(), "PRs and issues: who it is for (see toRoles).", fallback: .absent),
            .init("toRoles", .choices(ToRole.allCases.map(\.rawValue)), "Only with `to`: which ways it is for them. Leave it out for all (assigned, reviewRequested, mentioned; reviewRequested is PRs' alone), and never narrow it unless asked. Without `to`, it means nothing.",
                  fallback: .value(ToRole.allCases.map(\.rawValue))),
            .init("in", repos(), "Which repos. Required for workflows.", fallback: .absent),
            .init("on", .list(.string("branch")), "Workflows: branches (the repo's default branch when left out).", fallback: .absent),
            .init("named", .list(.string("workflow")), "Workflows: names (every workflow when left out).", fallback: .absent),
        ]),
        "Rule": .object([
            .init("id", .uuid, "Keep the id from get_category when updating; new rules get one.", fallback: .newUUID),
            .init("scope", .named("Scope"), "Which things the rule is about."),
            .init("match", .choice(MatchMode.allMatches), "`any`: one condition is enough; `all`: every one.", fallback: .value(MatchMode.any.rawValue)),
            .init("conditions", .list(.named("Condition")), "When the thing needs you. Empty: every open thing in scope.", fallback: .value([Any]())),
            .init("createdAt", .date, "Activity before this counts as old. Left out: now (an update keeps the rule's own).", fallback: .now),
        ]),
        "Action": .object([
            .init("id", .uuid, "Keep it when updating; new actions get one.", fallback: .newUUID),
            .init("kind", .tagged(actionVariants), "What it does."),
            .init("trigger", .choice(ActionTrigger.allMatches), "`enter`: once when a thing comes in; `eachFact`: once for each new fact.",
                  fallback: .value(ActionTrigger.enter.rawValue)),
        ]),
        "Category": .object([
            .init("id", .uuid, "Left out when creating.", fallback: .newUUID),
            .init("name", .string("name"), "What the bar and lists call it. Not empty; names are unique."),
            .init("symbol", .string("SF Symbol"), "An SF Symbol name, like `eye`, `bubble.left.and.bubble.right`, `star`, `cpu`."),
            .init("color", .choice(CategoryColor.allCases.map(\.rawValue)), "Its tint."),
            .init("rules", .list(.named("Rule")), "A thing is in the category if any rule matches.", fallback: .value([Any]())),
            .init("notifies", .bool, "Native notifications.", fallback: .value(true)),
            .init("hidden", .bool, "Hidden from the bar and muted; still collects.", fallback: .value(false)),
            .init("isCI", .bool, "The CI category only (can't be created or changed; it can be deleted).", fallback: .value(false)),
            .init("actions", .list(.named("Action")), "What it does by itself for a thing that comes in (never GitHub comments unless asked).",
                  fallback: .value([Any]())),
        ]),
        "Group": .object([
            .init("id", .uuid, "Left out when creating.", fallback: .newUUID),
            .init("name", .string("name"), "Not empty; names are unique."),
            .init("kind", .choice(InboxGroup.Kind.allMatches), "`people` (logins) or `repos` (`owner/repo`, `owner/*`)."),
            .init("members", .list(.string("login or owner/repo")), "Logins for people, `owner/repo` or `owner/*` for repos.", fallback: .value([Any]())),
        ]),
    ]

    /// The action kinds, from the model's own encoding of one of each (so a kind added or renamed there reaches the Router
    /// without a second list to keep).
    static var actionVariants: [JSONShape.Variant] {
        let samples: [(ActionKind, String)] = [
            (.askRouter(prompt: "prompt"), "Hands the thing to the Router with the prompt; it starts a session or passes it to one. `{repo} {number} {url}` are filled in; `{title}` and `{author}` point to the block of GitHub content that follows the prompt (what others wrote never goes in the prompt itself)."),
            (.comment("text"), "Comments on the PR or issue on GitHub. `{title} {url} {number} {repo} {author}` are filled in. Only when the user asked."),
            (.rerun, "Re-runs the failed jobs of the failing workflow runs (PRs and workflows)."),
        ]
        return samples.compactMap { kind, doc in
            guard let data = try? JSONEncoder().encode(kind), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let tag = object.keys.first else { return nil }
            let fields = (object[tag] as? [String: Any] ?? [:]).keys.sorted().map { JSONShape.Field($0, .string("text"), "") }
            return .init(tag, fields.isEmpty ? nil : .object(fields), doc)
        }
    }

    static func resolve(_ shape: JSONShape) -> JSONShape {
        if case .named(let name) = shape { return definitions[name] ?? shape }
        return shape
    }

    // MARK: JSON Schema

    /// The schema of a shape, its named shapes as `$defs` (with `$ref`s) so a repeated one is written once.
    static func schema(_ shape: JSONShape) -> [String: Any] {
        var used: [String] = []
        var out = schema(shape, used: &used)
        var defs: [String: Any] = [:]
        var queue = used
        while let name = queue.popLast() {
            guard defs[name] == nil, let definition = definitions[name] else { continue }
            var more: [String] = []
            defs[name] = schema(definition, used: &more)
            queue += more
        }
        if !defs.isEmpty { out["$defs"] = defs }
        return out
    }

    private static func schema(_ shape: JSONShape, used: inout [String]) -> [String: Any] {
        switch shape {
        case .string: return ["type": "string"]
        case .uuid: return ["type": "string", "format": "uuid"]
        case .date: return ["type": "string", "format": "date-time"]
        case .int: return ["type": "integer"]
        case .bool: return ["type": "boolean"]
        case .choice(let words): return ["type": "string", "enum": words]
        case .list(let item): return ["type": "array", "items": schema(item, used: &used)]
        case .choices(let words): return ["type": "array", "items": ["type": "string", "enum": words], "uniqueItems": true]
        case .named(let name):
            used.append(name)
            return ["$ref": "#/$defs/\(name)"]
        case .object(let fields):
            var properties: [String: Any] = [:]
            for field in fields {
                var property = schema(field.shape, used: &used)
                if !field.doc.isEmpty {
                    // A reference can't carry a description beside it in older drafts: wrap it.
                    property = property["$ref"] != nil ? ["description": field.doc, "allOf": [property]] : property.merging(["description": field.doc]) { a, _ in a }
                }
                properties[field.name] = property
            }
            var out: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
            let required = fields.filter { $0.fallback == nil }.map(\.name)
            if !required.isEmpty { out["required"] = required }
            return out
        case .tagged(let variants):
            return ["anyOf": variants.map { variant -> [String: Any] in
                let body = variant.body.map { schema($0, used: &used) } ?? ["type": "object", "properties": [String: Any](), "additionalProperties": false]
                return ["type": "object", "description": variant.doc, "properties": [variant.tag: body], "required": [variant.tag],
                        "additionalProperties": false]
            }]
        }
    }

    // MARK: Checking what the Router sent

    /// `value` made whole: unknown keys, wrong types and missing parts are faults (named by where), left-out fields get
    /// their fallbacks. What comes back is JSON the model's Codable reads. `now` and `ids` are what fallbacks use.
    static func normalize(_ value: Any, as shape: JSONShape, path: String = "", now: Date = Date()) throws -> Any {
        func fail(_ message: String) -> ShapeError { ShapeError(path: path, message: message) }
        func at(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }
        switch shape {
        case .named(let name):
            guard let definition = definitions[name] else { throw fail("unknown shape \(name)") }
            return try normalize(value, as: definition, path: path, now: now)
        case .string:
            guard value is String else { throw fail("must be a string") }
            return value
        case .uuid:
            guard let text = value as? String, UUID(uuidString: text) != nil else { throw fail("must be an id (a UUID)") }
            return text
        case .date:
            guard let text = value as? String, parseDate(text) != nil else { throw fail("must be an ISO 8601 date") }
            return text
        case .int:
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == n.doubleValue.rounded() else {
                throw fail("must be a whole number")
            }
            return n
        case .bool:
            guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw fail("must be true or false") }
            return n
        case .choice(let words):
            guard let text = value as? String, words.contains(text) else {
                throw fail("must be one of \(words.joined(separator: ", "))" + ((value as? String).map { " (not “\($0)”)" } ?? ""))
            }
            return text
        case .list(let item):
            guard let list = value as? [Any] else { throw fail("must be a list") }
            return try list.enumerated().map { try normalize($1, as: item, path: "\(path)[\($0)]", now: now) }
        case .choices(let words):
            guard let list = value as? [Any] else { throw fail("must be a list of \(words.joined(separator: ", "))") }
            var seen = Set<String>()
            return try list.enumerated().compactMap { i, item -> Any? in
                guard let text = item as? String, words.contains(text) else {
                    throw ShapeError(path: "\(path)[\(i)]", message: "must be one of \(words.joined(separator: ", "))")
                }
                return seen.insert(text).inserted ? text : nil
            }
        case .object(let fields):
            guard var object = value as? [String: Any] else { throw fail("must be an object") }
            let known = Set(fields.map(\.name))
            if let stray = object.keys.sorted().first(where: { !known.contains($0) }) {
                throw ShapeError(path: at(stray), message: "isn't a field here; the fields are \(fields.map(\.name).joined(separator: ", "))")
            }
            for field in fields {
                if let given = object[field.name] {
                    if given is NSNull, field.fallback != nil {
                        object[field.name] = nil
                    } else {
                        object[field.name] = try normalize(given, as: field.shape, path: at(field.name), now: now)
                        continue
                    }
                }
                guard let fallback = field.fallback else { throw ShapeError(path: at(field.name), message: "is missing") }
                switch fallback {
                case .absent: break
                case .value(let v): object[field.name] = v
                case .newUUID: object[field.name] = UUID().uuidString
                case .now: object[field.name] = formatDate(now)
                }
            }
            return object
        case .tagged(let variants):
            guard let object = value as? [String: Any] else {
                throw fail("must be an object with one key naming the case: \(variants.map(\.tag).joined(separator: ", "))")
            }
            guard object.count == 1, let tag = object.keys.first else {
                throw fail("must have exactly one key, one of \(variants.map(\.tag).joined(separator: ", "))")
            }
            guard let variant = variants.first(where: { $0.tag == tag }) else {
                throw ShapeError(path: at(tag), message: "isn't one of \(variants.map(\.tag).joined(separator: ", "))")
            }
            guard let body = variant.body else {
                guard let inner = object[tag] as? [String: Any], inner.isEmpty else {
                    throw ShapeError(path: at(tag), message: "takes no value; write {\"\(tag)\":{}}")
                }
                return object
            }
            return [tag: try normalize(object[tag] as Any, as: body, path: at(tag), now: now)]
        }
    }

    // MARK: Dates

    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parseDate(_ text: String) -> Date? { plain.date(from: text) ?? withFraction.date(from: text) }
    static func formatDate(_ date: Date) -> String { plain.string(from: date) }

    // MARK: Examples and grammar, written from the shapes

    /// A shape written out with placeholders, as the grammar shows it.
    static func example(_ shape: JSONShape) -> String {
        switch shape {
        case .string(let hint): return "\"<\(hint)>\""
        case .uuid: return "\"<id>\""
        case .date: return "\"<date>\""
        case .int: return "<n>"
        case .bool: return "true"
        case .choice(let words): return "\"" + words.joined(separator: "|") + "\""
        case .list(let item): return "[" + example(item) + ", …]"
        case .choices(let words): return "[\"" + words.joined(separator: "\", \"") + "\"]"
        case .named(let name): return name
        case .object(let fields):
            return "{" + fields.map { "\"\($0.name)\": \(example($0.shape))" }.joined(separator: ", ") + "}"
        case .tagged(let variants): return variants.map { example(variant: $0) }.joined(separator: " | ")
        }
    }

    static func example(variant: JSONShape.Variant) -> String {
        "{\"\(variant.tag)\": \(variant.body.map(example) ?? "{}")}"
    }
}

extension MatchMode { static var allMatches: [String] { [MatchMode.any, .all].map(\.rawValue) } }
extension ActionTrigger { static var allMatches: [String] { [ActionTrigger.enter, .eachFact].map(\.rawValue) } }
extension InboxGroup.Kind { static var allMatches: [String] { [InboxGroup.Kind.people, .repos].map(\.rawValue) } }
