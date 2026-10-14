import SwiftUI

// The Brief: Now written as prose. On top, what's for you and what's worth a look, in a few plain sentences; under it a
// paragraph per project saying where it stands. The parts that point at a session are tags the writer puts in the text,
// `<need s="…">`, `<look s="…">` and `<run s="…">`; the page draws them as highlights, marked with what their session is
// at now (read from its card, not from the words). Hovering one shows its card's gist, clicking opens the card under the
// paragraph and points the composer at it, so you answer as you do a card's. Whenever something comes in from a session,
// or from you, the writer (RouterDigestWriter.swift) rewrites the paragraphs it touches, and each rewrite is kept in the
// brief's history with what set it off, why, and a diff of what changed.

/// The Brief: the lead's two parts and a paragraph per project, in an order the app keeps (new projects at the end), and
/// its history.
struct RouterDigest: Codable, Equatable {
    struct Project: Codable, Equatable, Identifiable {
        /// The project's folder, as the canvas keys it.
        let folder: String
        var text: String
        var id: String { folder }
    }

    /// What needs you, in a few sentences.
    var forYou: String
    /// What's worth a look, in a sentence or two (empty: none).
    var worthALook: String
    var projects: [Project]
    /// When it was last rewritten.
    var at: Date
    /// Every rewrite, newest first: what set it off, what it changed and why.
    var history: [Revision] = []
    /// When you last left the Brief: what changed after it is marked new.
    var seenAt: Date?

    /// The history kept, newest first; older rewrites are dropped.
    static let historyLimit = 200

    init(forYou: String, worthALook: String, projects: [Project], at: Date, history: [Revision] = [], seenAt: Date? = nil) {
        self.forYou = forYou
        self.worthALook = worthALook
        self.projects = projects
        self.at = at
        self.history = history
        self.seenAt = seenAt
    }

    /// A paragraph's text by its key ("lead-you", "lead-look" or a project's folder); nil for a project not in it.
    func text(_ key: String) -> String? {
        switch key {
        case Revision.forYouKey: forYou
        case Revision.lookKey: worthALook
        default: projects.first { $0.folder == key }?.text
        }
    }

    /// The keys of the paragraphs a rewrite after `seenAt` changed.
    var changedSinceSeen: Set<String> {
        let since = seenAt ?? .distantPast
        return Set(history.prefix { $0.at > since }.flatMap { $0.changes.map(\.key) })
    }

    /// A rewrite of the brief: the events that set it off (a session's, yours), a label for it, why the text changed, and
    /// each paragraph it changed, before and after.
    struct Revision: Codable, Equatable, Identifiable {
        static let forYouKey = "lead-you"
        static let lookKey = "lead-look"

        enum Trigger: Codable, Equatable {
            /// Something came in from a session.
            case session(String)
            /// You said something (to the Router or a session).
            case you(String)
        }

        struct Change: Codable, Equatable {
            /// The paragraph: "lead-you", "lead-look" or a project's folder.
            let key: String
            let before: String
            let after: String
        }

        var id: String { "\(at.timeIntervalSince1970)" }
        let at: Date
        /// What set it off, first the one that matters most; several events close together make one rewrite.
        let triggers: [Trigger]
        /// What changed, in a few words.
        let label: String
        /// Why, in a sentence: what the event was and what it means for you.
        let why: String
        let changes: [Change]

        init(at: Date, triggers: [Trigger], label: String, why: String, changes: [Change]) {
            self.at = at
            self.triggers = triggers
            self.label = label
            self.why = why
            self.changes = changes
        }

        init(at: Date, trigger: Trigger, label: String, why: String, changes: [Change]) {
            self.init(at: at, triggers: [trigger], label: label, why: why, changes: changes)
        }
    }

    /// A rewrite recorded: newest first, the oldest past the limit dropped.
    mutating func record(_ revision: Revision) {
        history.insert(revision, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
    }
}

/// A unified diff of two paragraphs, tags read out, as a code review shows one: the text cut into sentences (a paragraph's
/// lines), sentences taken out and put in as − and + lines, the words that changed inside a sentence rewritten marked on
/// it, and the sentences kept shown only next to a change, the rest folded to ⋯.
enum DigestDiff {
    enum Line: Equatable {
        /// A sentence kept, shown as context.
        case same(String)
        /// Kept sentences folded away.
        case fold
        /// A sentence taken out, the ranges of its words that went (none: all of it).
        case removed(String, changed: [Range<String.Index>])
        /// A sentence put in, the ranges of its words that came.
        case added(String, changed: [Range<String.Index>])
    }

    static func lines(_ before: String, _ after: String) -> [Line] {
        let a = sentences(before), b = sentences(after)
        var ops: [(kind: Int, text: String)] = []  // 0 same, -1 removed, 1 added
        let diff = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) { ops.append((-1, a[i])); i += 1; continue }
            if j < b.count, inserted.contains(j) { ops.append((1, b[j])); j += 1; continue }
            if i < a.count, j < b.count { ops.append((0, b[j])); i += 1; j += 1; continue }
            if i < a.count { ops.append((-1, a[i])); i += 1 } else { ops.append((1, b[j])); j += 1 }
        }
        // A run of − lines then + lines is a rewrite: pair them, line by line, to mark the words that changed.
        var out: [Line] = []
        var k = 0
        while k < ops.count {
            if ops[k].kind == 0 { out.append(.same(ops[k].text)); k += 1; continue }
            var minus: [String] = [], plus: [String] = []
            while k < ops.count, ops[k].kind == -1 { minus.append(ops[k].text); k += 1 }
            while k < ops.count, ops[k].kind == 1 { plus.append(ops[k].text); k += 1 }
            var plusMarks: [[Range<String.Index>]] = plus.map { _ in [] }
            for (n, old) in minus.enumerated() {
                if n < plus.count {
                    let (gone, came) = changedWords(old, plus[n])
                    out.append(.removed(old, changed: gone))
                    plusMarks[n] = came
                } else {
                    out.append(.removed(old, changed: []))
                }
            }
            for (n, new) in plus.enumerated() { out.append(.added(new, changed: plusMarks[n])) }
        }
        return folded(out)
    }

    /// Kept sentences more than one away from a change folded to ⋯.
    static func folded(_ lines: [Line]) -> [Line] {
        let near: (Int) -> Bool = { index in
            [index - 1, index + 1].contains { n in
                guard lines.indices.contains(n) else { return false }
                if case .same = lines[n] { return false }
                return true
            }
        }
        var out: [Line] = []
        for (index, line) in lines.enumerated() {
            if case .same = line, !near(index) {
                if out.last != .fold { out.append(.fold) }
            } else {
                out.append(line)
            }
        }
        return out
    }

    /// The words of `old` that went and of `new` that came, as ranges in each.
    static func changedWords(_ old: String, _ new: String) -> ([Range<String.Index>], [Range<String.Index>]) {
        let a = wordRanges(old), b = wordRanges(new)
        let diff = b.map { new[$0] }.difference(from: a.map { old[$0] })
        var gone: [Int] = [], came: [Int] = []
        for change in diff {
            switch change {
            case .remove(let offset, _, _): gone.append(offset)
            case .insert(let offset, _, _): came.append(offset)
            }
        }
        return (runs(gone.sorted(), a), runs(came.sorted(), b))
    }

    /// Words next to each other marked as one run, the space between them with them.
    private static func runs(_ offsets: [Int], _ words: [Range<String.Index>]) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: Int?, last = -2
        for offset in offsets {
            if offset != last + 1, let s = start { out.append(words[s].lowerBound..<words[last].upperBound); start = nil }
            if start == nil { start = offset }
            last = offset
        }
        if let s = start { out.append(words[s].lowerBound..<words[last].upperBound) }
        return out
    }

    private static func wordRanges(_ text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            if text[index].isWhitespace {
                if let s = start { out.append(s..<index); start = nil }
            } else if start == nil {
                start = index
            }
        }
        if let s = start { out.append(s..<text.endIndex) }
        return out
    }

    /// The paragraph's sentences, its tags dropped (their text kept): cut after . ? ! or ; and the space after it.
    static func sentences(_ markup: String) -> [String] {
        let text = DigestMarkup.parse(markup).map { piece -> String in
            switch piece {
            case .text(let text): text
            case .span(_, _, let text): text
            }
        }
        .joined()
        var out: [String] = []
        var current = ""
        var previous: Character?
        for char in text {
            if char.isWhitespace, let p = previous, ".?!;".contains(p) {
                let sentence = current.trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { out.append(sentence) }
                current = ""
            } else {
                current.append(char)
            }
            previous = char
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { out.append(last) }
        return out
    }
}

/// The text with its tags read out.
enum DigestMarkup {
    enum Kind: String {
        case need, look, run

        var tint: Color {
            switch self {
            case .need: RouterZone.needs.tint
            case .look: CDS.Text.accent
            case .run: CDS.Text.muted
            }
        }
    }

    enum Piece: Equatable {
        case text(String)
        case span(Kind, session: String, text: String)
    }

    // swiftlint:disable:next force_try
    nonisolated(unsafe) private static let tag = try! Regex(#"<(need|look|run)\s+s="([^"]+)">(.*?)</\1>"#,
                                                            as: (Substring, Substring, Substring, Substring).self)

    /// The pieces in order; a tag it doesn't know, or one left open, is read as its text.
    static func parse(_ markup: String) -> [Piece] {
        var pieces: [Piece] = []
        var rest = Substring(markup)
        while let match = rest.firstMatch(of: tag) {
            let before = rest[rest.startIndex..<match.range.lowerBound]
            if !before.isEmpty { pieces.append(.text(String(before))) }
            if let kind = Kind(rawValue: String(match.output.1)) {
                pieces.append(.span(kind, session: String(match.output.2), text: String(match.output.3)))
            } else {
                pieces.append(.text(String(match.output.3)))
            }
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty { pieces.append(.text(String(rest))) }
        return pieces
    }
}

/// What the Brief keeps while the window lives: the highlight under the pointer and the card opened.
@Observable final class RouterDigestState {
    /// "paragraph#session" under the pointer.
    var hovered: String?
    /// "paragraph#session" opened under its paragraph.
    var open: String?
    /// The brief's history beside it.
    var historyOpen = false
    /// The rewrites opened to their diff.
    var expanded: Set<String> = []
}

// MARK: - Page

struct DigestPage: View {
    let store: Store
    let model: RouterModel

    static let column: CGFloat = 720

    var body: some View {
        let page = model.zones(store)
        let folders = model.canvasFolders(store, page: page)
        // Every tagged session resolves, not only the notes the canvas shows (it caps a project's at three).
        let items = Self.items(RouterCanvasModel.make(page: page, done: [], muted: Set(store.agents.mutedFolders),
                                                      name: store.routerProjectGroupName, color: { _ in nil }, showsAll: true,
                                                      projectKey: { store.routerProjectGroupKey(sessionID: $0, folder: $1) },
                                                      projectSource: store.routerProjectGroupSource))
        Scrolling {
            Group {
                if let digest = store.routerDigest {
                    let fresh = digest.changedSinceSeen
                    VStack(alignment: .leading, spacing: 28) {
                        lead(digest, items: items, page: page, fresh: fresh)
                        ForEach(digest.projects) { project in
                            let folder = folders.first { $0.key == project.folder }
                            DigestParagraph(store: store, model: model, page: page, items: items, key: project.folder,
                                            markup: project.text) {
                                HStack(spacing: 7) {
                                    Circle().fill(folder?.color ?? CDS.Text.muted).frame(width: 8, height: 8)
                                    Text(folder?.name ?? (project.folder as NSString).lastPathComponent)
                                        .font(CDS.sans(13, .semibold)).foregroundStyle(CDS.Text.primary)
                                    if fresh.contains(project.folder) { NewTag() }
                                }
                            }
                            .zIndex(model.digest.hovered?.hasPrefix(project.folder + "#") == true ? 1 : 0)
                        }
                    }
                } else {
                    empty
                }
            }
            .frame(maxWidth: Self.column, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, LaneMetrics.bottom)
            .frame(maxWidth: .infinity)
        }
        // The history, a column on the right, beside the text rather than over it.
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if model.digest.historyOpen, let digest = store.routerDigest {
                DigestHistory(store: store, model: model, digest: digest, folders: folders)
                    .frame(width: DigestHistory.width)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // Working sessions are kept current while it is on screen; left, what changes from now on is new when you come back.
        .onAppear { store.routerDigester.setVisible(true, store: store) }
        .onDisappear {
            store.routerDigester.setVisible(false, store: store)
            Self.markSeen(store)
        }
    }

    /// What was new has been seen: what changes after now is marked new.
    static func markSeen(_ store: Store, now: Date = Date()) {
        guard var digest = store.routerDigest, !digest.changedSinceSeen.isEmpty || digest.seenAt == nil else { return }
        digest.seenAt = now
        store.routerDigest = digest
    }

    /// No brief yet: the Router off, the first one being written, or nothing going on.
    @ViewBuilder private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Brief").font(CDS.sans(20, .semibold)).foregroundStyle(CDS.Text.primary)
            Group {
                if !store.router.enabled {
                    Text("Turn the Router on and the Brief will tell you what your sessions need, project by project.")
                } else if store.routerDigester.writing {
                    Text("Writing the brief…")
                } else if store.routerZones.needs.isEmpty && store.routerZones.notes.isEmpty && store.routerZones.working.isEmpty {
                    Text("Nothing going on. When a session finishes, asks something or gets stuck, it will be here.")
                } else {
                    Text("The brief will be written in a moment.")
                }
            }
            .font(CDS.sans(14)).foregroundStyle(CDS.Text.secondary)
        }
    }

    /// The lead: what's for you, then what's worth a look, each under its name in its colour.
    private func lead(_ digest: RouterDigest, items: [String: CanvasItem], page: RouterPage, fresh: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Text("Brief").font(CDS.sans(20, .semibold)).foregroundStyle(CDS.Text.primary)
                Spacer()
                if store.routerDigester.writing {
                    ProgressView().controlSize(.mini)
                }
                Text("updated " + agoPhrase(digest.at)).font(CDS.sans(12)).foregroundStyle(CDS.Text.muted)
                if !digest.history.isEmpty {
                    let on = model.digest.historyOpen
                    Button {
                        withAnimation(Motion.spatial.resolved(reduce: false)) { model.digest.historyOpen.toggle() }
                    } label: {
                        Label("History \(digest.history.count)", systemImage: "clock.arrow.circlepath")
                            .font(CDS.sans(12, .medium))
                            .foregroundStyle(on ? CDS.Text.primary : CDS.Text.secondary)
                            .padding(.horizontal, 8).frame(height: 24)
                            .background(Capsule().fill(on ? CDS.alpha(0.10) : CDS.alpha(0.05)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "Hide the brief's history" : "Show the brief's history")
                }
            }
            DigestParagraph(store: store, model: model, page: page, items: items, key: RouterDigest.Revision.forYouKey,
                            markup: digest.forYou, size: 16) {
                HStack(spacing: 7) {
                    Label("For you", systemImage: RouterZone.needs.symbol)
                        .font(CDS.sans(12, .semibold)).foregroundStyle(RouterZone.needs.tint)
                    if fresh.contains(RouterDigest.Revision.forYouKey) { NewTag() }
                }
            }
            .zIndex(model.digest.hovered?.hasPrefix("lead-you#") == true ? 2 : 1)
            if !digest.worthALook.isEmpty {
                DigestParagraph(store: store, model: model, page: page, items: items, key: RouterDigest.Revision.lookKey,
                                markup: digest.worthALook, size: 16) {
                    HStack(spacing: 7) {
                        Label("Worth a look", systemImage: RouterZone.notes.symbol)
                            .font(CDS.sans(12, .semibold)).foregroundStyle(CDS.Text.accent)
                        if fresh.contains(RouterDigest.Revision.lookKey) { NewTag() }
                        Spacer()
                        let looks = page.notes
                        if !looks.isEmpty {
                            Button {
                                for card in looks { store.setCardAddressed(card.id, true) }
                                Announce.say("Marked seen")
                            } label: {
                                Label(looks.count == 1 ? "Mark seen" : "Mark all seen", systemImage: "checkmark")
                                    .font(CDS.sans(11.5, .medium)).foregroundStyle(CDS.Text.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Mark everything worth a look as seen: it leaves the brief")
                        }
                    }
                }
                .zIndex(model.digest.hovered?.hasPrefix("lead-look#") == true ? 2 : 0)
            }
            Rectangle().fill(CDS.border).frame(height: CDS.hairline).padding(.top, 4)
        }
        .zIndex(model.digest.hovered?.hasPrefix("lead-") == true ? 2 : 0)
    }

    /// Each session's item on the page: what it is waiting on you for first, else what it is doing.
    static func items(_ folders: [CanvasFolder]) -> [String: CanvasItem] {
        var out: [String: CanvasItem] = [:]
        func rank(_ item: CanvasItem) -> Int {
            switch item {
            case .need, .ready: 0
            case .note: 1
            case .waiting: 2
            case .working: 3
            case .done: 4
            }
        }
        for item in folders.flatMap({ $0.groups.flatMap(\.items) }) {
            if let had = out[item.sessionID], rank(had) <= rank(item) { continue }
            out[item.sessionID] = item
        }
        return out
    }
}

/// "New": a paragraph a rewrite changed since you last left the Brief.
private struct NewTag: View {
    var body: some View {
        Text("New")
            .font(CDS.sans(CDS.Badge.font, .semibold))
            .foregroundStyle(CDS.BadgeTint.accentText)
            .padding(.horizontal, CDS.Badge.padX)
            .frame(height: CDS.Badge.height)
            .background(RoundedRectangle(cornerRadius: CDS.Badge.radius, style: .continuous).fill(CDS.BadgeTint.accentFill))
            .accessibilityLabel("Changed since you last looked")
    }
}

/// A paragraph of the brief: its name over it, the text with its highlights, and the card opened from it under it.
private struct DigestParagraph<Title: View>: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage
    let items: [String: CanvasItem]
    let key: String
    let markup: String
    var size: CGFloat = 15
    @ViewBuilder let title: Title

    var body: some View {
        let state = model.digest
        let opened = state.open.flatMap { $0.hasPrefix(key + "#") ? String($0.dropFirst(key.count + 1)) : nil }
        VStack(alignment: .leading, spacing: 8) {
            title
            DigestFlow(spacing: size * 0.27, lineSpacing: 5) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    switch token {
                    case .word(let word, let tight):
                        Text(word).font(CDS.sans(size)).foregroundStyle(CDS.Text.secondary)
                            .layoutValue(key: TightKey.self, value: tight)
                    case .span(let kind, let session, let text, let tight):
                        DigestSpan(store: store, model: model, page: page, item: items[session], kind: kind,
                                   id: key + "#" + session, session: session, text: text, size: size)
                            .layoutValue(key: TightKey.self, value: tight)
                            .zIndex(state.hovered == key + "#" + session ? 1 : 0)
                    }
                }
            }
            if let opened, let item = items[opened] {
                HStack(alignment: .top, spacing: 8) {
                    CanvasNode(item: item, store: store, model: model, page: page)
                        .frame(maxWidth: 560, alignment: .leading)
                    VStack(spacing: 6) {
                        Button {
                            withAnimation(Motion.spatial.resolved(reduce: false)) { state.open = nil }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(CDS.Text.muted)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(CDS.alpha(0.06)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close the card")
                        // Worth a look: seen, and it leaves the brief.
                        if case .note(let card) = item {
                            Button {
                                withAnimation(Motion.spatial.resolved(reduce: false)) { state.open = nil }
                                model.address(card.id, store: store)
                            } label: {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(CDS.Text.accent)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(CDS.Text.accent.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                            .help("Mark seen: it leaves the brief")
                            .accessibilityLabel("Mark seen")
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private enum Token {
        case word(String, tight: Bool)
        case span(DigestMarkup.Kind, session: String, text: String, tight: Bool)
    }

    /// The text cut into words and highlights; a word that follows a highlight without a space (its comma) sits against it.
    private var tokens: [Token] {
        var out: [Token] = []
        var glued = false
        for piece in DigestMarkup.parse(markup) {
            switch piece {
            case .text(let text):
                let startsTight = !(text.first?.isWhitespace ?? true)
                let words = text.split(whereSeparator: \.isWhitespace)
                for (i, word) in words.enumerated() {
                    out.append(.word(String(word), tight: i == 0 && startsTight && glued))
                }
                glued = !(text.last?.isWhitespace ?? true)
            case .span(let kind, let session, let text):
                out.append(.span(kind, session: session, text: text, tight: glued))
                glued = true
            }
        }
        return out
    }
}


// MARK: - History

/// The brief's history: each rewrite, newest first, in a line: who set it off (a session's icon, or you), what changed, and
/// when. Opened, why, then each paragraph it changed as a unified diff.
private struct DigestHistory: View {
    let store: Store
    let model: RouterModel
    let digest: RouterDigest
    let folders: [CanvasFolder]

    static let width: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("History").font(CDS.sans(12, .semibold)).foregroundStyle(CDS.Text.primary)
                Spacer()
                Text("\(digest.history.count) rewrites").font(CDS.sans(11)).foregroundStyle(CDS.Text.muted)
            }
            .padding(.horizontal, 12).frame(height: 34)
            Rectangle().fill(CDS.border).frame(height: CDS.hairline)
            Scrolling {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(digest.history) { revision in entry(revision) }
                }
                .padding(.vertical, 4)
                .padding(.bottom, LaneMetrics.bottom)
            }
        }
        .background(CDS.Surface.s2)
        .overlay(alignment: .leading) { Rectangle().fill(CDS.border).frame(width: CDS.hairline) }
    }

    private func entry(_ revision: RouterDigest.Revision) -> some View {
        let open = model.digest.expanded.contains(revision.id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Motion.spatial.resolved(reduce: false)) {
                    if open { model.digest.expanded.remove(revision.id) } else { model.digest.expanded.insert(revision.id) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(CDS.Text.muted).rotationEffect(.degrees(open ? 90 : 0)).frame(width: 8)
                    trigger(revision.triggers.first ?? .you("")).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    if revision.at > (digest.seenAt ?? .distantPast) {
                        Circle().fill(CDS.Text.accent).frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            .accessibilityLabel("New")
                    }
                    Text(revision.label).font(CDS.sans(12.5, .medium)).foregroundStyle(CDS.Text.primary)
                        .lineLimit(open ? nil : 1)
                    Spacer(minLength: 4)
                    Text(shortAgo(revision.at)).font(CDS.sans(11)).foregroundStyle(CDS.Text.muted).monospacedDigit()
                }
                .padding(.horizontal, 6).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(open ? CDS.alpha(0.05) : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    Text(revision.triggers.map(source).joined(separator: "; ") + ". " + revision.why)
                        .font(CDS.sans(11.5)).foregroundStyle(CDS.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(revision.changes.enumerated()), id: \.offset) { _, change in
                        diff(change)
                    }
                }
                .padding(.leading, 21).padding(.trailing, 6).padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
    }

    /// A paragraph's change as a code review shows a file's: its name on a bar, then its lines.
    private func diff(_ change: RouterDigest.Revision.Change) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Text(title(change.key)).font(CDS.mono(10.5, .medium)).foregroundStyle(CDS.Text.muted)
                .padding(.horizontal, 8).frame(height: 22).frame(maxWidth: .infinity, alignment: .leading)
                .background(CDS.alpha(0.04))
            Rectangle().fill(CDS.border).frame(height: CDS.hairline)
            ForEach(Array(DigestDiff.lines(change.before, change.after).enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(CDS.border, lineWidth: 1))
    }

    @ViewBuilder private func row(_ line: DigestDiff.Line) -> some View {
        switch line {
        case .fold:
            Text("⋯").font(CDS.mono(10.5)).foregroundStyle(CDS.Text.muted)
                .padding(.horizontal, 8).frame(height: 16).frame(maxWidth: .infinity, alignment: .leading)
                .background(CDS.alpha(0.02))
        case .same(let text):
            diffLine("", text, AttributedString(text), ink: CDS.Text.muted, ground: .clear)
        case .removed(let text, let changed):
            diffLine("−", text, marked(text, changed, Theme.red), ink: CDS.Text.secondary, ground: Theme.red.opacity(0.09))
        case .added(let text, let changed):
            diffLine("+", text, marked(text, changed, Theme.green), ink: CDS.Text.primary, ground: Theme.green.opacity(0.10))
        }
    }

    private func diffLine(_ sign: String, _ text: String, _ styled: AttributedString, ink: Color, ground: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(sign).font(CDS.mono(11, .medium)).foregroundStyle(ink.opacity(0.7)).frame(width: 8)
            Text(styled).font(CDS.sans(11.5)).foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8).padding(.vertical, 2.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ground)
    }

    /// The sentence with the words that changed in it on a stronger ground of the line's colour.
    private func marked(_ text: String, _ ranges: [Range<String.Index>], _ tint: Color) -> AttributedString {
        var out = AttributedString(text)
        for range in ranges {
            guard let lower = AttributedString.Index(range.lowerBound, within: out),
                  let upper = AttributedString.Index(range.upperBound, within: out) else { continue }
            out[lower..<upper].backgroundColor = tint.opacity(0.28)
        }
        return out
    }

    /// Who set it off: the session's own icon, or you.
    @ViewBuilder private func trigger(_ trigger: RouterDigest.Revision.Trigger) -> some View {
        switch trigger {
        case .session(let id):
            SessionMark(store: store, session: id, size: 15)
        case .you:
            Image(systemName: "person.fill").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(CDS.Text.accent)
                .frame(width: 16, height: 16)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(CDS.Text.accent.opacity(0.14)))
        }
    }

    private func source(_ trigger: RouterDigest.Revision.Trigger) -> String {
        switch trigger {
        case .session(let id): "From “\(store.claudeSessions[id]?.title ?? "a session")”"
        case .you(let said): "You said “\(said)”"
        }
    }

    private func title(_ key: String) -> String {
        switch key {
        case "lead-you": "For you"
        case "lead-look": "Worth a look"
        default: folders.first { $0.key == key }?.name ?? (key as NSString).lastPathComponent
        }
    }
}

/// What a highlight's session is at, in a mark and a colour: what it asks of you (its card's kind), worth a look, ready to go
/// on, waiting, or working.
struct DigestState {
    let symbol: String
    let tint: Color
    let label: String

    /// Its card handled since the text was written.
    static let handled = DigestState(symbol: "checkmark.circle.fill", tint: CDS.Text.muted, label: "Done")

    init(symbol: String, tint: Color, label: String) {
        (self.symbol, self.tint, self.label) = (symbol, tint, label)
    }

    init(_ item: CanvasItem?, kind: DigestMarkup.Kind) {
        switch item {
        case .need(let c), .done(let c):
            (symbol, tint, label) = (c.kind.symbol, c.kind.color, c.kind.label)
        case .ready:
            (symbol, tint, label) = ("arrow.right.circle.fill", CDS.Text.accent, "Ready to go on")
        case .note:
            (symbol, tint, label) = (RouterZone.notes.symbol, CDS.Text.accent, "Worth a look")
        case .waiting:
            (symbol, tint, label) = (RouterZone.waiting.symbol, RouterTriage.waitingTint, "Waiting")
        case .working:
            (symbol, tint, label) = ("ellipsis", CDS.Text.muted, "Working")
        case nil:
            (symbol, tint, label) = ("circle", kind.tint, "")
        }
    }
}

/// A highlight: its state's mark, its words on a ground of its state's colour, and its session's own icon after them, so
/// you see which session it is and what it's at before you hover it. Hovered, its card's gist floats under it; clicked,
/// the card opens under the paragraph and the composer answers it.
private struct DigestSpan: View {
    let store: Store
    let model: RouterModel
    let page: RouterPage
    let item: CanvasItem?
    let kind: DigestMarkup.Kind
    let id: String
    let session: String
    let text: String
    let size: CGFloat

    /// The open card an item is, if it has one.
    static func cardID(_ item: CanvasItem) -> String? {
        switch item {
        case .need(let c), .ready(let c), .note(let c): c.id
        default: nil
        }
    }

    var body: some View {
        let state = model.digest
        let hovered = state.hovered == id
        let open = state.open == id
        // Handled since the text was written (answered, archived, seen): a check at once, before the rewrite says so.
        let finished: Bool = { if case .done = item { true } else { item == nil } }()
        let handled = finished && store.router.cards.last(where: { $0.sessionID == session }).map { !$0.isOpen } == true
        let status = handled ? DigestState.handled : DigestState(item, kind: kind)
        let quiet = kind == .run
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Button {
            withAnimation(Motion.spatial.resolved(reduce: false)) {
                state.open = open ? nil : id
                state.hovered = nil
            }
            if !open, let item {
                switch item {
                case .need(let c), .ready(let c), .note(let c): model.select(c.id, store: store, reveal: false)
                default: break
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: status.symbol)
                    .font(.system(size: size * 0.66, weight: .semibold))
                    .foregroundStyle(status.tint)
                Text(text)
                    .font(CDS.sans(size, quiet ? .regular : .medium))
                    .foregroundStyle(quiet ? CDS.Text.primary : status.tint)
                    .overlay(alignment: .bottom) {
                        if quiet {
                            Rectangle().fill(CDS.Text.muted.opacity(hovered ? 0.9 : 0.4)).frame(height: 1).offset(y: 1)
                        }
                    }
                SessionMark(store: store, session: session, size: size)
            }
            .padding(.horizontal, quiet ? 0 : 5)
            .padding(.vertical, 1)
            .background {
                if !quiet { shape.fill(status.tint.opacity(hovered || open ? 0.24 : 0.11)) }
            }
            .overlay { if open { shape.strokeBorder(status.tint.opacity(0.7), lineWidth: 1) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { state.hovered = id } else if state.hovered == id { state.hovered = nil }
        }
        .overlay(alignment: .topLeading) {
            if hovered, !open, let item {
                DigestPeek(item: item, page: page)
                    .frame(width: 400, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: size + 14)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .contextMenu {
            if let item, let card = DigestSpan.cardID(item) {
                Button("Open card") {
                    withAnimation(Motion.spatial.resolved(reduce: false)) { state.open = id }
                    model.select(card, store: store, reveal: false)
                }
                if case .note = item {
                    Button("Mark seen") { model.address(card, store: store) }
                } else {
                    Button("Archive") { model.address(card, store: store) }
                }
            }
        }
        .accessibilityLabel(status.label.isEmpty ? text : "\(text), \(status.label)")
        .accessibilityHint(item == nil ? "" : "Opens its card")
    }
}

/// A session's own icon, small and quiet, as the sidebar and its card show it: its symbol, else its letters or emoji.
private struct SessionMark: View {
    let store: Store
    let session: String
    let size: CGFloat

    var body: some View {
        let entry = store.agents.entries.first { $0.id == session }
        Group {
            if let icon = entry?.icon, entry?.label == nil {
                Image(systemName: icon).font(.system(size: size * 0.62, weight: .medium))
            } else {
                Text(entry?.label ?? initials).font(CDS.sans(size * 0.55, .semibold))
            }
        }
        .foregroundStyle(CDS.Text.muted)
        .frame(width: size * 1.05, height: size * 1.05)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(CDS.alpha(0.06)))
        .help(store.claudeSessions[session]?.title ?? "")
    }

    private var initials: String {
        let words = (store.claudeSessions[session]?.title ?? "").split(separator: " ").prefix(2)
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// What a highlight points at, floating over the text while hovered: the session, what kind of thing it is, what it says
/// and what it asks. Click to open the card itself.
private struct DigestPeek: View {
    let item: CanvasItem
    let page: RouterPage

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(CDS.sans(13, .semibold)).foregroundStyle(CDS.Text.primary).lineLimit(1)
                if let card { KindTag(kind: card.kind) }
                Spacer(minLength: 4)
                Text(shortAgo(at)).font(CDS.sans(11)).foregroundStyle(CDS.Text.muted)
            }
            if !text.isEmpty {
                Text(LocalizedStringKey(text)).font(CDS.sans(12.5)).foregroundStyle(CDS.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let asks = card?.asks, !asks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(asks, id: \.question) { ask in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(CDS.Text.muted)
                            Text(LocalizedStringKey(ask.question)).foregroundStyle(CDS.Text.primary)
                        }
                        .font(CDS.sans(12.5))
                    }
                }
            }
            Text("Click to open and answer").font(CDS.sans(11)).foregroundStyle(CDS.Text.muted)
        }
        .padding(12)
        .background(shape.fill(CDS.Surface.s3))
        .overlay(shape.strokeBorder(CDS.borderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
    }

    private var card: RouterCard? {
        switch item {
        case .need(let c), .ready(let c), .note(let c), .waiting(let c), .done(let c): c
        case .working: nil
        }
    }

    private var title: String {
        switch item {
        case .working(let row): row.session.title
        default: card?.title ?? ""
        }
    }

    private var text: String {
        switch item {
        case .working(let row): row.activity?.text ?? page.summaries[row.id]?.text ?? ""
        default: card.map { $0.brief ?? $0.text } ?? ""
        }
    }

    private var at: Date {
        switch item {
        case .working(let row): row.activity?.since ?? row.session.lastActivity
        default: card?.createdAt ?? Date()
        }
    }
}

// MARK: - Flow

private struct TightKey: LayoutValueKey { static let defaultValue = false }

/// Words and highlights laid out as text is: left to right, onto the next line when the line is full, each line's items on
/// a shared middle. A tight item sits against the one before it.
struct DigestFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(subviews, width: width)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            for (index, x, size) in line.items {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: y + (line.height - size.height) / 2),
                                      proposal: size.width > bounds.width ? ProposedViewSize(width: bounds.width, height: nil) : ProposedViewSize(size))
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [(Int, CGFloat, CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = [Line()]
        for (index, view) in subviews.enumerated() {
            var size = view.sizeThatFits(.unspecified)
            // Wider than a line: it wraps within one rather than overflowing.
            if size.width > width, width.isFinite { size = view.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            let gap = view[TightKey.self] || lines[lines.count - 1].items.isEmpty ? 0 : spacing
            if !lines[lines.count - 1].items.isEmpty, lines[lines.count - 1].width + gap + size.width > width {
                lines.append(Line())
            }
            var line = lines[lines.count - 1]
            let x = line.items.isEmpty ? 0 : line.width + gap
            line.items.append((index, x, size))
            line.width = x + size.width
            line.height = max(line.height, size.height)
            lines[lines.count - 1] = line
        }
        return lines
    }
}
