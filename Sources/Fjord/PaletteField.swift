import AppKit
import SwiftUI

// The palette's query field: a real NSTextField, so that dead keys and input methods finish before the palette sees
// anything, and its keys arrive as commands (`control(_:textView:doCommandBy:)`), not as key codes.

struct PaletteField: NSViewRepresentable {
    let model: PaletteModel
    /// What the field says when it is empty.
    let placeholder: String
    /// What it is typed with: the model's query, which it follows when the model sets it (back from the actions page).
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> PaletteFieldHost {
        let host = PaletteFieldHost()
        let field = host.field
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = CDS.nsSans(CDS.Palette.fontSize)
        field.textColor = NSColor(CDS.Text.primary)
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.allowsEditingTextAttributes = false
        field.setAccessibilityLabel("Search")
        field.delegate = context.coordinator
        field.model = model
        return host
    }

    func updateNSView(_ host: PaletteFieldHost, context: Context) {
        let field = host.field
        context.coordinator.model = model
        field.model = model
        if context.coordinator.placeholder != placeholder {
            context.coordinator.placeholder = placeholder
            field.placeholderAttributedString = NSAttributedString(
                string: placeholder, attributes: [.font: CDS.nsSans(CDS.Palette.fontSize), .foregroundColor: NSColor(CDS.Text.muted)])
        }
        // The model's text, unless the field already shows it or an input method is composing in it.
        let composing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if !composing, field.stringValue != text { field.stringValue = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView host: PaletteFieldHost, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: CDS.Palette.fieldHeight)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var model: PaletteModel
        var placeholder = ""

        init(_ model: PaletteModel) { self.model = model }

        /// Filters on what was typed, never while an input method holds marked text.
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            let span = LatencySignposts.signposter.beginInterval("Palette key to flush")
            model.setQuery(field.stringValue)
            LatencySignposts.endAfterCommit("Palette key to flush", span)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            // An input method composing: its keys are its own.
            if textView.hasMarkedText() { return false }
            switch command {
            case #selector(NSResponder.moveUp(_:)):
                model.move(down: false)
            case #selector(NSResponder.moveDown(_:)):
                model.move(down: true)
            case #selector(NSResponder.insertNewline(_:)):
                model.runSelected()
            case #selector(NSResponder.insertTab(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertLineBreak(_:)):
                model.showActions()
            case #selector(NSResponder.insertBacktab(_:)):
                break
            case #selector(NSResponder.cancelOperation(_:)):
                model.escape()
            case #selector(NSResponder.deleteBackward(_:)):
                return textView.string.isEmpty && model.backspaceOnEmpty()
            default:
                return false
            }
            return true
        }
    }
}

/// Holds the field at its own height in the middle of the row's 32pt (as a CSS input centres its text).
final class PaletteFieldHost: NSView {
    let field = PaletteTextField()

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(field)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let height = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
    }
}

/// The field itself: it takes the keyboard as it enters the window, and types the keys that opened the palette.
final class PaletteTextField: NSTextField {
    weak var model: PaletteModel?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // On the next run-loop turn: the window's first responder is not settled while the view is being put in.
        DispatchQueue.main.async { [weak self] in self?.takeKeyboard() }
    }

    private func takeKeyboard() {
        guard let window, window.makeFirstResponder(self), let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = NSColor(CDS.Text.primary)
        editor.selectedTextAttributes = [.backgroundColor: NSColor(CDS.Text.accent).withAlphaComponent(0.35)]
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        typePendingKeys(into: editor)
    }

    /// With the field editor up, the keys that opened the palette are typed into it (a dead key, an input method's first key,
    /// a plain letter), as the inbox search did.
    private func typePendingKeys(into editor: NSTextView) {
        guard let model, !model.pendingKeys.isEmpty else { return }
        let keys = model.pendingKeys
        model.pendingKeys = []
        keys.forEach(editor.keyDown(with:))
    }
}
