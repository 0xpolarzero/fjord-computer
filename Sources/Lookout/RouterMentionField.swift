import AppKit
import SwiftUI

/// The composer's text with @project mentions inline: each is an atomic pill (one `MentionAttachment` character) where it was
/// typed. `RouterModel.draft` holds the text with one `mark` per pill, `RouterModel.tokens` the pills' folders in the same
/// order; what goes to the Router has each mark written back as "@name".
enum MentionText {
    /// The character an attachment is in a text storage.
    static let mark: Character = "\u{FFFC}"
    static let markString = String(mark)

    static func isBreak(_ c: Character) -> Bool { c.isWhitespace || c == mark }

    /// The draft as the Router gets it: each pill as "@name".
    static func plain(_ draft: String, tokens: [String], name: (String) -> String) -> String {
        var next = tokens.makeIterator()
        var out = ""
        for c in draft {
            if c == mark, let folder = next.next() { out += "@" + name(folder) } else { out.append(c) }
        }
        return out
    }

    /// The text storage's text (a mark for each pill) and its pills' folders in order.
    static func serialize(_ text: NSAttributedString) -> (draft: String, tokens: [String]) {
        var tokens: [String] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let pill = value as? MentionAttachment { tokens.append(pill.folder) }
        }
        return (text.string, tokens)
    }

    /// The pasted text with each "@name" of a known project (`resolve`: name → folder) made a pill. The word must stand
    /// alone (after a break or the start, before a break or the end); the longest name wins.
    static func pills(in text: String, names: [(name: String, folder: String)]) -> (draft: String, tokens: [String]) {
        let sorted = names.sorted { $0.name.count > $1.name.count }
        let chars = Array(text)
        var out = ""
        var tokens: [String] = []
        var i = 0
        while i < chars.count {
            if chars[i] == "@", i == 0 || isBreak(chars[i - 1]) {
                let rest = chars[(i + 1)...]
                if let hit = sorted.first(where: { entry in
                    let n = Array(entry.name)
                    guard !n.isEmpty, rest.count >= n.count, Array(rest.prefix(n.count)).map({ String($0).lowercased() }) == n.map({ String($0).lowercased() }) else { return false }
                    let end = rest.startIndex + n.count
                    return end == chars.endIndex || isBreak(chars[end]) || ",.;:!?)".contains(chars[end])
                }) {
                    out.append(mark)
                    tokens.append(hit.folder)
                    i += 1 + hit.name.count
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return (out, tokens)
    }
}

/// A pill in the text: the project's colour dot and its name on a rounded fill.
final class MentionAttachment: NSTextAttachment {
    let folder: String
    let name: String

    init(folder: String, name: String, color: Color?, font: NSFont) {
        self.folder = folder
        self.name = name
        super.init(data: nil, ofType: nil)
        let label = "@" + name
        let pillFont = NSFont(descriptor: font.fontDescriptor, size: font.pointSize - 1) ?? font
        let ink = NSAttributedString(string: label, attributes: [.font: pillFont, .foregroundColor: NSColor(CDS.Text.primary)])
        let textWidth = ceil(ink.size().width)
        let dot: CGFloat = color == nil ? 0 : 6
        let width = 6 + (dot > 0 ? dot + 4 : 0) + textWidth + 6
        let height: CGFloat = 18
        let dotColor = color.map(NSColor.init)
        image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            NSColor(CDS.Fill.secondary).setFill()
            shape.fill()
            var x: CGFloat = 6
            if let dotColor {
                dotColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: (height - dot) / 2, width: dot, height: dot)).fill()
                x += dot + 4
            }
            ink.draw(at: NSPoint(x: x, y: (height - ink.size().height) / 2))
            return true
        }
        // Centred on the text's line.
        bounds = CGRect(x: 0, y: font.descender + ((font.ascender - font.descender) - height) / 2, width: width, height: height)
    }

    required init?(coder: NSCoder) { fatalError("not archived") }
}

/// The composer's text view: pills copy as "@name", a paste of "@name" of a known project becomes a pill, and its focus is
/// told.
final class MentionTextView: NSTextView {
    var onFocus: (Bool) -> Void = { _ in }
    /// The known projects' names and folders, for a paste.
    var known: () -> [(name: String, folder: String)] = { [] }
    var makePill: (String) -> MentionAttachment? = { _ in nil }
    var name: (String) -> String = { $0 }
    var base: [NSAttributedString.Key: Any] = [:]

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocus(false) }
        return ok
    }

    /// The selection as text, each pill as "@name".
    func plain(_ range: NSRange) -> String {
        guard let part = textStorage?.attributedSubstring(from: range) else { return "" }
        let (draft, tokens) = MentionText.serialize(part)
        return MentionText.plain(draft, tokens: tokens, name: name)
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plain(range), forType: .string)
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        if selectedRange().length > 0 { insertText("", replacementRange: selectedRange()) }
    }

    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        insertPlain(text, replacing: selectedRange())
    }

    /// Inserts text, its "@name"s of known projects as pills.
    func insertPlain(_ text: String, replacing range: NSRange) {
        let (draft, tokens) = MentionText.pills(in: text, names: known())
        let out = NSMutableAttributedString()
        var next = tokens.makeIterator()
        var run = ""
        func flush() { if !run.isEmpty { out.append(NSAttributedString(string: run, attributes: base)); run = "" } }
        for c in draft {
            if c == MentionText.mark, let folder = next.next(), let pill = makePill(folder) {
                flush()
                out.append(NSAttributedString(attachment: pill))
            } else { run.append(c) }
        }
        flush()
        out.addAttributes(base, range: NSRange(location: 0, length: out.length))
        // Attachments keep their own attribute; the base has none.
        guard shouldChangeText(in: range, replacementString: out.string) else { return }
        textStorage?.replaceCharacters(in: range, with: out)
        setSelectedRange(NSRange(location: range.location + out.length, length: 0))
        didChangeText()
    }

}

/// The composer's field: a growing text view (up to `maxHeight`, then it scrolls) with the pills inline.
struct MentionField: NSViewRepresentable {
    let store: Store
    let model: RouterModel
    let maxHeight: CGFloat
    let editable: Bool
    /// Bumped to ask for the keyboard.
    let focusTick: Int
    let onFocus: (Bool) -> Void

    private static var role: (CGFloat, CGFloat) { CDS.Density.compact.prose }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = MentionTextView(frame: .zero, textContainer: container)
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainerInset = .zero
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.importsGraphics = false
        view.insertionPointColor = NSColor(CDS.Text.primary)
        view.selectedTextAttributes = [.backgroundColor: NSColor(CDS.Text.accent).withAlphaComponent(0.35)]
        view.setAccessibilityLabel("Message the Router")
        view.setAccessibilityHelp("Return sends, Shift Return starts a new line, @ tags a project")
        view.delegate = context.coordinator
        context.coordinator.view = view

        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? MentionTextView else { return }
        let c = context.coordinator
        c.model = model
        c.store = store
        let (font, base) = Self.attributes()
        view.base = base
        view.font = font
        view.isEditable = editable
        view.isSelectable = editable
        view.known = { [store] in store.knownFolders.filter { !$0.isEmpty }.map { (store.folderName($0), $0) } }
        view.name = { [store] in store.folderName($0) }
        view.makePill = { [store] folder in
            MentionAttachment(folder: folder, name: store.folderName(folder), color: store.projectColor(folder), font: font)
        }
        view.onFocus = onFocus
        // The model's text, when the view isn't already showing it (a pick, a send, a draft set from outside).
        let shown = MentionText.serialize(view.attributedString())
        if (shown.draft != model.draft || shown.tokens != model.tokens), !view.hasMarkedText() {
            c.syncing = true
            let text = NSMutableAttributedString()
            var tokens = model.tokens.makeIterator()
            var run = ""
            func flush() { if !run.isEmpty { text.append(NSAttributedString(string: run, attributes: base)); run = "" } }
            for ch in model.draft {
                if ch == MentionText.mark, let folder = tokens.next(), let pill = view.makePill(folder) {
                    flush()
                    text.append(NSAttributedString(attachment: pill))
                } else { run.append(ch) }
            }
            flush()
            let keep = view.selectedRange()
            view.textStorage?.setAttributedString(text)
            view.setSelectedRange(NSRange(location: min(keep.location, text.length), length: 0))
            view.typingAttributes = base
            c.syncing = false
        }
        if c.focusTick != focusTick {
            c.focusTick = focusTick
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        scroll.verticalScrollElasticity = .none
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let view = scroll.documentView as? MentionTextView, let layout = view.layoutManager,
              let container = view.textContainer else { return nil }
        let width = proposal.width ?? 300
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let content = max(20, ceil(layout.usedRect(for: container).height))
        let height = min(content, maxHeight)
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = content > maxHeight ? .allowed : .none
        return CGSize(width: width, height: height)
    }

    static func attributes() -> (NSFont, [NSAttributedString.Key: Any]) {
        let font = CDS.nsSans(role.0)
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = role.1
        style.maximumLineHeight = role.1
        let offset = (role.1 - (font.ascender - font.descender)) / 2
        return (font, [.font: font, .foregroundColor: NSColor(CDS.Text.primary), .paragraphStyle: style,
                       .baselineOffset: offset])
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var view: MentionTextView?
        var model: RouterModel?
        var store: Store?
        var focusTick = 0
        var syncing = false

        func textDidChange(_ notification: Notification) {
            guard !syncing, let view, let model else { return }
            let (draft, tokens) = MentionText.serialize(view.attributedString())
            if model.tokens != tokens { model.tokens = tokens }
            if model.draft != draft { model.draft = draft }
            view.typingAttributes = view.base
            view.invalidateIntrinsicContentSize()
            view.enclosingScrollView?.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let view, !view.hasMarkedText() { view.typingAttributes = view.base }
        }
    }
}
