import Foundation

// Which of the Router's changes to Lookout wait for you. A run acts on your message, but it reads what sessions and GitHub
// wrote, and words there could try to steer it. So a change whose effect reaches outside Lookout (an action that comments on
// GitHub, starts sessions or re-runs CI by itself; what such a category runs on, or what reaches it past the categories
// before it; session titles sent to TypeSafe), one that
// takes something away (a category or group deleted, many things marked at once), and one your message didn't speak of (a
// setting it never named, marks it never asked for) is not applied: its card says why, with Apply and Discard. A local change
// you asked for applies at once, with Revert.

enum LookoutGate {
    /// Things marked at once beyond which marking waits for Apply.
    static let manyMarks = 5

    /// Why `change` waits for your Apply, or nil when it applies at once. `request`: your message for the run;
    /// `categories`: the categories as they are now.
    static func reason(_ change: LookoutChange, request: String, categories: [InboxCategory]) -> String? {
        let said = words(request)
        switch change.patch {
        case .category(let index, let before, let after):
            guard let after else { return "Deleting a category waits for you" }
            // By value and by count: an action copied (the same one twice) runs twice, so it is as new as one never there.
            var had = Dictionary((before?.actions.items ?? []).map { ($0, 1) }, uniquingKeysWith: +)
            let new = after.actions.items.filter { action in
                guard let left = had[action], left > 0 else { return true }
                had[action] = left - 1
                return false
            }
            if !new.isEmpty {
                return "It adds an action that runs by itself (" + new.map(\.title).joined(separator: ", ") + ")"
            }
            if !after.actions.isEmpty, before?.rules != after.rules {
                return "It changes what a category with actions runs on"
            }
            // A thing goes to the first category that takes it: what an earlier one takes (its rules, whether it is shown)
            // decides what reaches a later one with actions.
            let routes = before.map { $0.rules != after.rules || $0.hidden != after.hidden } ?? !after.rules.isEmpty
            if routes {
                let at = categories.firstIndex { $0.id == after.id } ?? min(max(index, 0), categories.count)
                let later = categories[at...].filter { $0.id != after.id && !$0.actions.isEmpty }
                if !later.isEmpty {
                    return "It changes what reaches a later category with actions (" + later.map(\.title).joined(separator: ", ") + ")"
                }
            }
            return nil
        case .group(_, let before, let after):
            guard let after else { return "Deleting a group waits for you" }
            guard before != nil else { return nil }
            // Those with actions, and those before one: what they take decides what reaches it.
            let lastActing = categories.lastIndex { !$0.actions.isEmpty } ?? -1
            let users = categories.enumerated().filter { i, c in
                uses(c, group: after.id) && (!c.actions.isEmpty || i < lastActing)
            }.map(\.element)
            return users.isEmpty ? nil : "Categories with actions, or before one, use this group (" + users.map(\.title).joined(separator: ", ") + ")"
        case .order(let before, let after):
            let acting = Set(categories.filter { !$0.actions.isEmpty }.map(\.id))
            guard !acting.isEmpty else { return nil }
            let moved = acting.contains { before.firstIndex(of: $0) != after.firstIndex(of: $0) }
                || before.filter { !acting.contains($0) } != after.filter { !acting.contains($0) }
            return moved ? "The order decides which category's actions run on a thing" : nil
        case .setting(let key, _, let after):
            if key == "sessionIcons", case .on(true) = after { return "It sends your sessions' titles to TypeSafe" }
            guard let topic = topics[key], !said.contains(where: { word in topic.contains { word.hasPrefix($0) } }) else { return nil }
            return "Your message didn't speak of this setting"
        case .marks(_, let changes):
            if changes.count > manyMarks { return "It marks \(changes.count) things at once" }
            return said.contains(where: { word in markWords.contains { word.hasPrefix($0) } }) ? nil : "Your message didn't ask to mark anything"
        }
    }

    /// Why marking `changes` waits beyond the change's own reasons: together with what this turn marked already, more than
    /// `manyMarks` things (however the marking was split); or a thing your message doesn't name (`named`).
    static func marksReason(_ changes: [EntryChange], named: Set<String>, markedThisTurn: Set<String>) -> String? {
        let total = markedThisTurn.union(changes.map(\.thing)).count
        if total > manyMarks { return "It marks \(total) things in this run" }
        let unnamed = changes.filter { !named.contains($0.thing) }.count
        return unnamed == 0 ? nil : "Your message didn't name \(unnamed == 1 ? "a thing" : "\(unnamed) things") it marks"
    }

    /// Whether your message names a thing: its reference (`owner/repo#12`), its number (`#12`), its whole title, or the
    /// category it is marked by (`category`, when the marking is by category).
    static func names(_ request: String, thing: Thing, category: String?) -> Bool {
        let said = request.lowercased()
        if let number = thing.number {
            if mentions(said, ref: "\(thing.repo)#\(number)") { return true }
            if said.range(of: #"(?<![\w/])#\#(number)(?!\d)"#, options: .regularExpression) != nil { return true }
        }
        let title = (thing.kind == .workflow ? thing.workflowName ?? thing.title : thing.title).lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if title.count >= 4, said.contains(title) { return true }
        if let category = category?.lowercased().trimmingCharacters(in: .whitespaces), category.count >= 2,
           said.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: category))\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Whether `text` says `ref` (`owner/repo#12`, or `owner/repo`) as a whole: not part of a longer one (`acme/api#123` is
    /// not `acme/api#12`, `acme/api-v2` is not `acme/api`, nor is `acme/api#12` the repo alone).
    static func mentions(_ text: String, ref: String) -> Bool {
        let tail = ref.contains("#") ? #"(?!\d)"# : #"(?![\w/-]|\.\w|#\d)"#
        let pattern = #"(?<![\w./-])"# + NSRegularExpression.escapedPattern(for: ref.lowercased()) + tail
        return text.lowercased().range(of: pattern, options: .regularExpression) != nil
    }

    /// The words that name each setting (a word of your message starting with one counts).
    private static let topics: [String: [String]] = [
        "notifications": ["notif", "banner", "alert", "mute", "silen", "quiet", "disturb"],
        "snooze": ["snooze", "notif", "banner", "alert", "mute", "silen", "quiet", "disturb", "pause"],
        "pollInterval": ["interval", "poll", "often", "frequen", "check", "refresh", "second", "minute", "sync"],
        "centerBar": ["center", "centre", "middle", "bar"],
        "launchAtLogin": ["login", "log", "launch", "start", "boot"],
        "sessionIcons": ["icon"],
    ]

    private static let markWords = ["done", "seen", "read", "unread", "mark", "restor", "clear", "archiv", "dismiss", "ack", "undone", "reopen", "back"]

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// Whether a category's rules name the group (by its id, anywhere in them).
    private static func uses(_ category: InboxCategory, group: UUID) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(category.rules) else { return true }
        return String(decoding: data, as: UTF8.self).contains(group.uuidString)
    }
}

extension LookoutChange {
    /// Made, but waiting for your Apply (or Discard): nothing of it is applied yet.
    var isPending: Bool { pending != nil && !isReverted }
    /// Discarded before it was applied.
    var isDiscarded: Bool { pending != nil && isReverted }
}

extension Store {
    /// Applies a change that waited for you, as it was made: what it touched goes to its state after. Nil when it can't
    /// (not waiting, or no longer kept).
    @discardableResult
    func applyLookoutChange(_ id: UUID, now: Date = Date()) -> LookoutChange? {
        guard let i = router.changes.firstIndex(where: { $0.id == id }), router.changes[i].isPending else { return nil }
        var change = router.changes[i]
        let decision = router.decisions.first { $0.links.changes.contains(id) }?.id
        do {
            try changingInbox(.routerTool(decision: decision)) { try applyPatch(change.patch) }
        } catch {
            change.revertNote = "Couldn't apply it: \(error.localizedDescription)"
            router.changes[i] = change
            return change
        }
        change.pending = nil
        router.changes[i] = change
        return change
    }

    /// Lets a waiting change go: nothing of it was applied, and nothing is.
    @discardableResult
    func discardLookoutChange(_ id: UUID, now: Date = Date()) -> LookoutChange? {
        guard let i = router.changes.firstIndex(where: { $0.id == id }), router.changes[i].isPending else { return nil }
        var change = router.changes[i]
        change.revertedAt = now
        change.revertNote = "Discarded"
        router.changes[i] = change
        noteReverted(change.id)
        return change
    }

    /// What a change makes of what it touched: its after.
    func applyPatch(_ patch: LookoutChange.Patch) throws {
        switch patch {
        case .category(let index, let before, let after):
            if let after {
                if let i = categories.firstIndex(where: { $0.id == after.id }) { categories[i] = after }
                else { categories.insert(after, at: min(max(index, 0), categories.count)) }
            } else if let before, let i = categories.firstIndex(where: { $0.id == before.id }) {
                categories.remove(at: i)
            }
            categoriesChangedByRouter()
        case .group(let index, let before, let after):
            if let after {
                if let i = groups.firstIndex(where: { $0.id == after.id }) { groups[i] = after }
                else { groups.insert(after, at: min(max(index, 0), groups.count)) }
            } else if let before, let i = groups.firstIndex(where: { $0.id == before.id }) {
                groups.remove(at: i)
            }
            categoriesChangedByRouter()
        case .order(_, let after):
            categories = Self.ordered(categories, by: after)
            categoriesChangedByRouter()
        case .setting(let key, _, let after):
            try LookoutSetting.named(key)?.apply(self, after)
        case .marks(_, let changes):
            for item in changes { marks[item.thing] = item.after }
        }
    }
}
