import Foundation
import os

// What changed the inbox's categories and groups, and from where, in the unified log:
//   /usr/bin/log show --predicate 'subsystem == "dev.polarzero.lookout" AND category == "inbox"' --info --last 1h
// One choke point: `Store.categories` and `Store.groups` diff what they held against what they hold on every set, and say
// who set them (`Store.inboxSource`, set around the change by its caller; the categories page and the bar's own controls
// when nobody did).

/// Who changed the categories or groups.
enum InboxChangeSource: Equatable, CustomStringConvertible {
    /// New category's Create.
    case newCategoryButton
    /// The category editor, the categories page's rows and groups, the sidebar's and the bar's toggles.
    case editor
    /// A Router tool, in the run with this decision.
    case routerTool(decision: UUID?)
    case undo
    case redo
    /// A Router change's Revert.
    case revert
    /// The state file, at launch.
    case load
    /// A repo renamed on GitHub, rewritten in rules and groups by a sync.
    case sync

    var description: String {
        switch self {
        case .newCategoryButton: "newCategoryButton"
        case .editor: "editor"
        case .routerTool(let decision): "routerTool(decision: \(decision?.uuidString ?? "none"))"
        case .undo: "undo"
        case .redo: "redo"
        case .revert: "revert"
        case .load: "load"
        case .sync: "sync"
        }
    }
}

enum InboxLog {
    static let subsystem = "dev.polarzero.lookout"
    static let logger = Logger(subsystem: subsystem, category: "inbox")

    static func write(_ line: String) {
        logger.notice("\(line, privacy: .public)")
    }

    /// One line per category made, deleted or changed (the fields that changed), and one for a new order.
    static func categories(from old: [InboxCategory], to new: [InboxCategory], source: InboxChangeSource) -> [String] {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lines: [String] = []
        for (i, c) in new.enumerated() {
            guard let was = before[c.id] else {
                lines.append("category created \(label(c.name, c.id)) at \(i) [\(c.color.rawValue), \(c.symbol), \(c.rules.count) rule(s)] by \(source)")
                continue
            }
            if was != c {
                let fields = changedFields(was, c)
                let renamed = was.name != c.name ? " (was \(quoted(was.name)))" : ""
                lines.append("category updated \(label(c.name, c.id))\(renamed): \(fields.joined(separator: ", ")) by \(source)")
            }
        }
        for c in old where after[c.id] == nil {
            lines.append("category deleted \(label(c.name, c.id)) by \(source)")
        }
        let kept = old.map(\.id).filter { after[$0] != nil }, keptNow = new.map(\.id).filter { before[$0] != nil }
        if kept != keptNow {
            lines.append("categories reordered: \(new.map { quoted($0.name) }.joined(separator: ", ")) by \(source)")
        }
        return lines
    }

    static func groups(from old: [InboxGroup], to new: [InboxGroup], source: InboxChangeSource) -> [String] {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lines: [String] = []
        for g in new {
            guard let was = before[g.id] else {
                lines.append("group created \(label(g.name, g.id)) [\(g.kind.rawValue), \(g.members.count) member(s)] by \(source)")
                continue
            }
            var fields: [String] = []
            if was.name != g.name { fields.append("name (was \(quoted(was.name)))") }
            if was.kind != g.kind { fields.append("kind") }
            if was.members != g.members { fields.append("members (\(was.members.count) → \(g.members.count))") }
            if !fields.isEmpty { lines.append("group updated \(label(g.name, g.id)): \(fields.joined(separator: ", ")) by \(source)") }
        }
        for g in old where after[g.id] == nil {
            lines.append("group deleted \(label(g.name, g.id)) by \(source)")
        }
        if old.map(\.id).filter({ after[$0] != nil }) != new.map(\.id).filter({ before[$0] != nil }) {
            lines.append("groups reordered: \(new.map { quoted($0.name) }.joined(separator: ", ")) by \(source)")
        }
        return lines
    }

    private static func changedFields(_ a: InboxCategory, _ b: InboxCategory) -> [String] {
        var out: [String] = []
        if a.name != b.name { out.append("name") }
        if a.symbol != b.symbol { out.append("symbol") }
        if a.color != b.color { out.append("color") }
        if a.rules != b.rules { out.append("rules (\(a.rules.count) → \(b.rules.count))") }
        if a.notifies != b.notifies { out.append("notifies \(b.notifies)") }
        if a.hidden != b.hidden { out.append("hidden \(b.hidden)") }
        if a.actions != b.actions { out.append("actions") }
        if a.section != b.section { out.append("section") }
        if out.isEmpty { out.append("other") }
        return out
    }

    private static func quoted(_ name: String) -> String { "“\(name)”" }
    private static func label(_ name: String, _ id: UUID) -> String { "\(quoted(name)) \(id.uuidString)" }
}

extension Store {
    /// Runs `body` with its changes to the categories and groups put down to `source` in the log.
    func changingInbox<T>(_ source: InboxChangeSource, _ body: () throws -> T) rethrows -> T {
        let previous = inboxSource
        inboxSource = source
        defer { inboxSource = previous }
        return try body()
    }

    func logCategories(from old: [InboxCategory]) {
        guard old != categories else { return }
        InboxLog.categories(from: old, to: categories, source: inboxSource ?? .editor).forEach(inboxLog)
    }

    func logGroups(from old: [InboxGroup]) {
        guard old != groups else { return }
        InboxLog.groups(from: old, to: groups, source: inboxSource ?? .editor).forEach(inboxLog)
    }
}
