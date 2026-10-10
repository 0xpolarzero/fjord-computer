import AppKit
import SwiftUI

/// Where you write to the Router, drawn as the Claude Code tab's composer (docs/design/spec/composer-overlays.md): the
/// context strip over the card (the card the message replies to, with its ×; Backspace at the start takes it off) and the
/// card (Return sends, ⇧Return starts a new line, see `RouterKeys`). Typing @ suggests projects over the caret (↑↓, Return
/// or Tab picks, Esc dismisses); a pick is a pill in the text where the @ was (see `MentionField`). Once typing pauses, Jev's
/// pick of where the message goes is a ghost chip in the strip, its card or row marked on the page: a click fixes it, Esc
/// waves it off (see `RouterLiveTarget`). Stop while the Router works.
struct RouterComposer: View {
    let store: Store
    @Bindable var model: RouterModel
    /// Mirrors the text view's first responder; `focusTick` asks it for the keyboard.
    @State private var focused = false
    @State private var focusTick = 0
    /// The suggestions' height, to hang them over the caret.
    @State private var listHeight: CGFloat = 0
    /// Where the field is in its window: tells its text view from every other one.
    @State private var anchor = FieldAnchor()
    /// The @ word's first character in the card (x from its leading edge, y of its line's top from its top), once known.
    @State private var mentionAt: CGPoint?
    @State private var windowHeight: CGFloat = 0
    @State private var hovering = false
    @State private var overButton = false
    @Environment(\.colorSchemeContrast) private var contrast

    private typealias C = CDS.Composer

    var body: some View {
        let working = store.routerDispatcher.isBusy
        let on = model.canSend(store)
        let suggestions = model.suggestions(store)
        VStack(alignment: .leading, spacing: 0) {
            // Who your words go to, as the Code tab's strip over its composer: the card's session, the projects you tagged.
            if model.replyTo != nil || model.live.pinned != nil || model.live.prediction != nil {
                strip.padding(.bottom, C.dockGap)
            }
            card(on: on, working: working)
                // Over the card, so it never pushes the chat about.
                .overlay(alignment: .topLeading) {
                    if !suggestions.isEmpty {
                        let at = mentionAt ?? CGPoint(x: 0, y: C.pad + (C.row - 20) / 2)
                        MentionList(suggestions: suggestions, index: model.mentionIndex,
                                    hover: { model.mentionIndex = $0 }) { model.pickMention($0) }
                            .fixedSize()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                            .offset(x: max(0, at.x), y: at.y - C.mentionOffset - listHeight)
                            .transition(.opacity)
                    }
                }
                .zIndex(1)
        }
        .motion(Theme.Motion.fade, value: suggestions.map(\.folder))
        .motion(Theme.Motion.fade, value: model.live.prediction?.target)
        // Jev's pick follows the draft and what fixes its target; the page marks its card or row while it shows.
        .onChange(of: model.draft) { model.predictTarget(store: store) }
        .onChange(of: model.tokens) { model.predictTarget(store: store) }
        .onChange(of: model.replyTo) { model.predictTarget(store: store) }
        .onChange(of: model.live.pinned) { model.predictTarget(store: store) }
        .onChange(of: model.live.prediction?.mark) { old, new in model.markPrediction(from: old, to: new) }
        .onChange(of: model.highlighted) { _, now in
            if now == nil, let mark = model.live.prediction?.mark { model.highlighted = mark }
        }
        .onAppear {
            if on { requestFocus() }
            model.predictTarget(store: store)
        }
        .onChange(of: model.focusRequest) { requestFocus() }
        .onChange(of: focused) { _, now in
            model.composerFocused = now
            if now { DispatchQueue.main.async { typePendingKeys() } }
        }
        .onDisappear {
            model.composerFocused = false
            model.markPrediction(from: model.live.prediction?.mark, to: nil)
            // Nothing of the draft goes to Jev while the composer isn't there.
            model.live.suspend()
        }
        // The @ suggestions follow the caret, wherever it is in the text.
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { note in
            // Only the composer's own editor, while it edits: in its window, where its field is (not another window's, nor a
            // form's "Other…"), and still the window's first responder (ending its editing, when the composer loses the
            // keyboard, moves the editor's selection; that isn't the caret moving).
            guard let editor = note.object as? NSTextView, anchor.owns(editor), editor.window?.firstResponder === editor
            else { return }
            model.followCaret(editor)
            mentionAt = mentionPoint(editor)
        }
        .onChange(of: model.caretRequest) { _, request in
            guard let request else { return }
            model.caretRequest = nil
            // After the field has the new text.
            DispatchQueue.main.async {
                guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                let at = min(request, (editor.string as NSString).length)
                editor.setSelectedRange(NSRange(location: at, length: 0))
                model.followCaret(editor)
                mentionAt = mentionPoint(editor)
            }
        }
    }

    // MARK: Strip

    /// The card the message replies to, removable.
    private var strip: some View {
        FlowLayout(spacing: C.stripGap) {
            if let id = model.replyTo, let card = store.router.cards.first(where: { $0.id == id }) {
                ComposerChip(symbol: "arrow.right", text: card.title, tint: card.kind.color,
                             removeLabel: "Stop replying to \(card.title)") { model.replyTo = nil }
            }
            if model.live.pinned != nil, let title = model.live.pinnedTitle {
                ComposerChip(symbol: "arrow.right", text: title, tint: CDS.Text.accent,
                             removeLabel: "Let the Router decide where this goes") { model.live.reset() }
            }
            if let prediction = model.live.prediction {
                PredictionChip(prediction: prediction) { model.pinPrediction(store: store) }
            }
        }
        .padding(CDS.Density.compact.pad.md)
        .frame(maxWidth: .infinity, minHeight: C.stripHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: C.stripRadius, style: .continuous).fill(CDS.alpha(0.05)))
    }

    // MARK: Card

    private func card(on: Bool, working: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: C.radius, style: .continuous)
        let hot = focused || (hovering && !overButton)
        let ring = contrast == .increased ? CDS.Text.primary.opacity(0.5) : hot ? C.ringHot : C.ring
        return ZStack(alignment: .bottomTrailing) {
            field(on: on)
                .padding(.leading, C.pad + C.textInset)
                // The actions' `pl-1.5` and their 28 pt cell.
                .padding(.trailing, C.pad + 6 + C.row)
                .padding(.vertical, C.pad + (C.row - 20) / 2)
                .frame(maxWidth: .infinity, minHeight: C.minHeight, alignment: .topLeading)
            action(on: on, working: working)
                .onHover { overButton = $0 }
                .padding(C.pad)
        }
        .background(shape.fill(CDS.Surface.s3))
        .background(AnchorView(anchor: anchor) { windowHeight = $0 })
        .overlay(shape.strokeBorder(ring, lineWidth: 1))
        .shadow(color: focused ? C.dropFocus : C.drop, radius: 10, y: 4)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onTapGesture { if on { focusTick &+= 1 } }
        .animation(.easeOut(duration: 0.2), value: hot)
    }

    private func field(on: Bool) -> some View {
        // `min(24rem, 40svh)` less the card's padding, in 20 pt lines.
        let limit = min(C.maxHeight, windowHeight > 0 ? windowHeight * C.maxHeightShare : C.maxHeight)
        let lines = max(1, Int((limit - 2 * C.pad - (C.row - 20)) / 20))
        let placeholder = model.replyTo == nil ? "Tell the Router what to pass on, or ask" : "Reply, or tell the Router"
        return MentionField(store: store, model: model, maxHeight: CGFloat(lines) * 20, editable: on, focusTick: focusTick) {
            focused = $0
        }
        .frame(minHeight: 20)
        .background(alignment: .topLeading) {
            if model.draft.isEmpty {
                Text(placeholder).cdsText(CDS.Density.compact.prose, .regular, CDS.Text.muted)
                    .lineLimit(1).truncationMode(.tail)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    /// Claude's ghost icon button: send (ArrowReturn) or, while the Router works, stop (StopCircle).
    @ViewBuilder private func action(on: Bool, working: Bool) -> some View {
        if working {
            GhostIcon(symbol: "stop.circle", label: "Stop") { store.routerDispatcher.stopAll() }
                .accessibilityHint("Stops the Router's runs")
                .tip("Stop", "Stops the Router's runs")
        } else {
            let empty = !on || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            GhostIcon(symbol: "arrow.turn.down.left", label: "Send") { model.send(store: store) }
                .disabled(empty)
                .tip("Send", "Return · ⇧Return for a new line")
        }
    }

    // MARK: Caret

    /// Where the @ word before the caret starts, in the card: x of its "@", y of its line's top.
    private func mentionPoint(_ editor: NSTextView) -> CGPoint? {
        guard let view = anchor.view, let window = editor.window else { return nil }
        let text = editor.string as NSString
        let caret = editor.selectedRange().location
        guard caret != NSNotFound, caret <= text.length else { return nil }
        let at = text.range(of: "@", options: .backwards, range: NSRange(location: 0, length: caret))
        let range = at.location == NSNotFound ? NSRange(location: caret, length: 0) : NSRange(location: at.location, length: 1)
        let screen = editor.firstRect(forCharacterRange: range, actualRange: nil)
        guard screen != .zero else { return nil }
        let local = view.convert(window.convertPoint(fromScreen: CGPoint(x: screen.minX, y: screen.maxY)), from: nil)
        let top = view.isFlipped ? local.y : view.bounds.height - local.y
        return CGPoint(x: local.x, y: top)
    }

    private func requestFocus() {
        DispatchQueue.main.async {
            focusTick &+= 1
            DispatchQueue.main.async { typePendingKeys() }
        }
    }

    /// The keys that sent the focus here (typing with no field focused), typed into the composer in order.
    private func typePendingKeys() {
        guard !model.pendingKeys.isEmpty,
              let editor = (model.pendingKeys.first?.window ?? NSApp.keyWindow)?.firstResponder as? NSTextView else { return }
        let keys = model.pendingKeys
        model.pendingKeys = []
        editor.moveToEndOfDocument(nil)
        keys.forEach(editor.keyDown(with:))
    }
}

/// CDS's ghost icon-only Button in the composer's 28 pt row: transparent, white 7.5% on hover, radius 6, a 16 pt glyph in
/// the primary ink; 40% when disabled.
private struct GhostIcon: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(CDS.Text.primary)
                .frame(width: CDS.Composer.row, height: CDS.Composer.row)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous),
                                          rest: .clear, hover: CDS.Fill.ghostHover, active: CDS.Fill.ghostSelected,
                                          pressed: CDS.Fill.ghostSelected))
        .accessibilityLabel(label)
    }
}

/// A chip in the strip over the composer, as the Code tab's diff chip (24 pt, radius 6, white 10%, `shadow-field`): what
/// goes with the message, in the strip's mono 13 muted, and a ghost × to take it off.
struct ComposerChip: View {
    let symbol: String?
    let text: String
    let tint: Color
    let removeLabel: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(tint).accessibilityHidden(true)
            }
            Text(text).font(CDS.mono(13)).foregroundStyle(CDS.Text.muted).lineLimit(1).truncationMode(.tail)
            ChipClose(label: removeLabel, action: remove)
        }
        .padding(.leading, CDS.Density.compact.pad.md)
        .padding(.trailing, 3)
        .frame(height: CDS.Density.compact.control)
        .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous).fill(CDS.Fill.secondary)
            .shadow(color: CDS.fieldShadow, radius: 1, y: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text)
    }
}

/// Jev's pick while you type: a ghost of the reply chip (dashed, no fill, no ×), muted; a click fixes it as the target.
private struct PredictionChip: View {
    let prediction: RouterLiveTarget.Prediction
    let pin: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
        Button(action: pin) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .medium)).foregroundStyle(CDS.Text.muted)
                    .accessibilityHidden(true)
                Text(prediction.title).font(CDS.mono(13)).foregroundStyle(hovering ? CDS.Text.secondary : CDS.Text.muted)
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, CDS.Density.compact.pad.md)
            .frame(height: CDS.Density.compact.control)
            .background(shape.fill(hovering ? CDS.Fill.ghostHover : .clear))
            .overlay(shape.strokeBorder(CDS.border, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .tip("Jev thinks this goes to \(prediction.detail)", "Click to fix it, Esc to clear")
        .accessibilityLabel("Jev thinks this goes to \(prediction.detail)")
        .accessibilityHint("Fixes it as where the message goes")
    }
}

/// The chip's ×: ghost, muted, primary and white 7.5% on hover.
private struct ChipClose: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                .foregroundStyle(hovering ? CDS.Text.primary : CDS.Text.muted)
                .frame(width: CDS.Density.compact.controlNested, height: CDS.Density.compact.controlNested)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(hovering ? CDS.Fill.ghostHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

/// The @ suggestions as Claude's MentionDropdown: the projects the word matches, the one ↑↓ (or the pointer) picked lit.
struct MentionList: View {
    let suggestions: [(folder: String, name: String)]
    let index: Int
    var hover: ((Int) -> Void)? = nil
    let pick: (String) -> Void

    var body: some View {
        let d = CDS.Density.compact
        let shape = RoundedRectangle(cornerRadius: d.panelRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.folder) { i, project in
                Button { pick(project.folder) } label: {
                    HStack(spacing: d.gap.xs) {
                        Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(CDS.Text.secondary)
                            .frame(width: d.icon, height: d.icon)
                        HStack(alignment: .firstTextBaseline, spacing: d.gap.xs) {
                            Text("@" + project.name).font(CDS.sans(d.body.0)).foregroundStyle(CDS.Text.primary)
                                .lineLimit(1).layoutPriority(1)
                            Text(Self.shortPath(project.folder)).font(CDS.sans(d.caption.0)).foregroundStyle(CDS.Text.muted)
                                .lineLimit(1).truncationMode(.head)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, d.pad.md)
                    .frame(height: d.control)
                    .background(RoundedRectangle(cornerRadius: d.radius, style: .continuous)
                        .fill(i == index ? CDS.Fill.ghostHover : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { hover?(i) } }
                .accessibilityLabel("Project \(project.name)")
                .accessibilityAddTraits(i == index ? .isSelected : [])
            }
        }
        .padding(d.pad.xs)
        .frame(width: CDS.Composer.mentionWidth)
        .background(shape.fill(CDS.Surface.s3))
        .overlay(shape.strokeBorder(CDS.border, lineWidth: 1))
        .shadow(color: CDS.PanelShadow.near.color, radius: CDS.PanelShadow.near.radius, y: CDS.PanelShadow.near.y)
        .shadow(color: CDS.PanelShadow.far.color, radius: CDS.PanelShadow.far.radius, y: CDS.PanelShadow.far.y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Projects")
    }

    /// `~/code/lookout` rather than the whole path.
    static func shortPath(_ folder: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }
}

/// The composer field's place on screen, kept by an empty AppKit view behind it: a text view is the composer's when it is in
/// the same window and inside the field (SwiftUI doesn't hand out the field's own text view). It also tells its window's
/// height, for the field's `min(24rem, 40svh)`.
final class FieldAnchor {
    weak var view: NSView?

    func owns(_ editor: NSTextView) -> Bool {
        guard let view, let window = view.window, editor.window === window else { return false }
        let field = view.convert(view.bounds, to: nil)
        let text = editor.convert(editor.bounds, to: nil)
        return field.contains(CGPoint(x: text.midX, y: text.midY))
    }
}

private struct AnchorView: NSViewRepresentable {
    let anchor: FieldAnchor
    var windowHeight: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> WindowWatcher {
        let view = WindowWatcher()
        view.report = windowHeight
        anchor.view = view
        return view
    }

    func updateNSView(_ view: WindowWatcher, context: Context) {
        anchor.view = view
        view.report = windowHeight
    }

    final class WindowWatcher: NSView {
        var report: (CGFloat) -> Void = { _ in }
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            send(window)
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window,
                                                              queue: .main) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated { self?.send(window) }
            }
        }

        private func send(_ window: NSWindow) {
            let height = window.contentLayoutRect.height
            DispatchQueue.main.async { [report] in report(height) }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
