import AppKit
import SwiftUI

/// The composer's text with its @ pills inline (a project, a session, a notification, a category: `RouterPointer`): each is
/// an atomic pill (one `MentionAttachment` character) where it was typed. `RouterModel.draft` holds the text with one `mark`
/// per pill, `RouterModel.pointers` what the pills point to in the same order; what goes to the Router has each mark written
/// back as "@name".
enum MentionText {
    /// The character an attachment is in a text storage.
    static let mark: Character = "\u{FFFC}"
    static let markString = String(mark)

    static func isBreak(_ c: Character) -> Bool { c.isWhitespace || c == mark }

    /// The draft as the Router gets it: each pill as "@name".
    static func plain(_ draft: String, pointers: [RouterPointer], name: (RouterPointer) -> String) -> String {
        var next = pointers.makeIterator()
        var out = ""
        for c in draft {
            if c == mark, let pointer = next.next() { out += "@" + name(pointer) } else { out.append(c) }
        }
        return out
    }

    /// The text storage's text (a mark for each pill) and what its pills point to, in order.
    static func serialize(_ text: NSAttributedString) -> (draft: String, pointers: [RouterPointer]) {
        var pointers: [RouterPointer] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let pill = value as? MentionAttachment { pointers.append(pill.pointer) }
        }
        return (text.string, pointers)
    }
}

/// A pill in the text (`MentionPill`): its symbol or its project's colour dot, and its name, on a rounded fill.
final class MentionAttachment: NSTextAttachment {
    let pointer: RouterPointer
    let look: MentionLook

    init(pointer: RouterPointer, look: MentionLook, font: NSFont) {
        self.pointer = pointer
        self.look = look
        super.init(data: nil, ofType: nil)
        let image = MentionPill.image(look, font: font)
        self.image = image
        // Centred on the text's line.
        let height = MentionPill.height
        bounds = CGRect(x: 0, y: font.descender + ((font.ascender - font.descender) - height) / 2, width: image.size.width,
                        height: height)
    }

    /// A project's pill: its colour's dot (none: no dot) and its name.
    convenience init(folder: String, name: String, color: Color?, font: NSFont) {
        self.init(pointer: .project(folder), look: MentionLook(label: name, symbol: nil, tint: color), font: font)
    }

    required init?(coder: NSCoder) { fatalError("not archived") }
}

/// The composer's text view: pills copy as "@name", a paste is plain text (a pill is made only by picking from the @
/// suggestions: pasted code's `@cache` stays the decorator it is), and its focus is told.
final class MentionTextView: NSTextView {
    var onFocus: (Bool) -> Void = { _ in }
    var makePill: (RouterPointer) -> MentionAttachment? = { _ in nil }
    var name: (RouterPointer) -> String = { _ in "" }
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
        let (draft, pointers) = MentionText.serialize(part)
        return MentionText.plain(draft, pointers: pointers, name: name)
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

    /// Inserts text as it is: an "@name" in it, a project's or not, stays text.
    func insertPlain(_ text: String, replacing range: NSRange) {
        let out = NSAttributedString(string: text, attributes: base)
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
    /// What VoiceOver calls the field, and its hint (nil: the composer's).
    var label = "Message the Router"
    var hint: String? = nil
    /// A key's command (`moveUp:`, `insertNewline:`, `cancelOperation:`…) before the text view does it: true when it was
    /// handled. For a field outside the Router's page, whose keys `RouterKeys` doesn't see (a "Then" prompt).
    var onCommand: ((Selector) -> Bool)? = nil
    /// The selection moved (the caret, for the @ suggestions), with the text view.
    var onSelection: ((NSTextView) -> Void)? = nil

    private static var role: (CGFloat, CGFloat) { CDS.Density.compact.prose }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        storage.delegate = context.coordinator
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
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(hint ?? "Return sends, Shift Return starts a new line, @ tags a project, a session, a notification or a category, or inserts a snippet")
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
        c.onCommand = onCommand
        c.onSelection = onSelection
        model.editor = view
        let (font, base) = Self.attributes()
        view.base = base
        view.font = font
        view.isEditable = editable
        view.isSelectable = editable
        view.name = { [store] in store.pointerName($0) }
        view.makePill = { [store] pointer in MentionAttachment(pointer: pointer, look: store.pointerLook(pointer), font: font) }
        view.onFocus = onFocus
        // The model's text, when the view isn't already showing it (a pick, a send, a draft set from outside).
        let shown = MentionText.serialize(view.attributedString())
        if (shown.draft != model.draft || shown.pointers != model.pointers), !view.hasMarkedText() {
            c.syncing = true
            let text = NSMutableAttributedString()
            var pointers = model.pointers.makeIterator()
            var run = ""
            func flush() { if !run.isEmpty { text.append(NSAttributedString(string: run, attributes: base)); run = "" } }
            for ch in model.draft {
                if ch == MentionText.mark, let pointer = pointers.next(), let pill = view.makePill(pointer) {
                    flush()
                    text.append(NSAttributedString(attachment: pill))
                } else { run.append(ch) }
            }
            flush()
            let keep = view.selectedRange()
            view.textStorage?.setAttributedString(text)
            view.setSelectedRange(NSRange(location: min(keep.location, text.length), length: 0))
            view.typingAttributes = base
            c.fits.removeAll()
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
        // A layout asks for the same sizes over and over (the page around it settling): the text is laid out once per width
        // and text, not on every ask.
        let key = Coordinator.Fit(width: width, text: view.string)
        let content: CGFloat
        if let known = context.coordinator.fits[key] {
            content = known
            // The container at the width asked for, as a fresh layout leaves it (laid out again only when drawn).
            if container.size.width != width { container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude) }
        } else {
            container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            layout.ensureLayout(for: container)
            content = max(20, ceil(layout.usedRect(for: container).height))
            if context.coordinator.fits.count >= 16 { context.coordinator.fits.removeAll() }
            context.coordinator.fits[key] = content
        }
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
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        weak var view: MentionTextView?
        var model: RouterModel?
        var store: Store?
        var focusTick = 0
        var syncing = false
        var onCommand: ((Selector) -> Bool)?
        var onSelection: ((NSTextView) -> Void)?
        /// The text's height at a width, for the text it had then (a pill is one character of it; pills made anew clear it).
        var fits: [Fit: CGFloat] = [:]

        struct Fit: Hashable {
            var width: CGFloat
            var text: String
        }

        /// The text changed by the view's undo or redo (⌘Z), which tells its delegate nothing: the model follows it here, or
        /// the next update would put the text back.
        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated {
                guard !syncing, let model, view?.undoManager?.isUndoing == true || view?.undoManager?.isRedoing == true
                else { return }
                let (draft, pointers) = MentionText.serialize(textStorage)
                if model.pointers != pointers { model.pointers = pointers }
                if model.draft != draft { model.draft = draft }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !syncing, let view, let model else { return }
            let (draft, pointers) = MentionText.serialize(view.attributedString())
            if model.pointers != pointers { model.pointers = pointers }
            if model.draft != draft { model.draft = draft }
            view.typingAttributes = view.base
            view.invalidateIntrinsicContentSize()
            view.enclosingScrollView?.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let view, !view.hasMarkedText() { view.typingAttributes = view.base }
            if let view { onSelection?(view) }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            return onCommand?(commandSelector) ?? false
        }
    }
}
