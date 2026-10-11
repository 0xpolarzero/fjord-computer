import SwiftUI

// Claude's Code-tab approval cards and its CDS Button, as Claude's own code draws them (docs/design/spec/forms-buttons.md,
// dark, comfortable density): the inline AskUserQuestion card (§1A) and its receipt, the plan card (§2) in its card
// shell, and Button (§4) with its keycaps (§4.6).

// MARK: - Questions

/// A question form as Claude's inline AskUserQuestion card (§1A): one question at a time ("1 of N" with carets), the
/// question on a white-5% header, the options as rows with a radio (one choice) or a checkbox (several), "Other" with its
/// own field, then Next / Submit. Once answered, the receipt: each question and what was answered.
///
/// Claude's footer also has Skip. Lookout can't send a skipped answer (the hook only takes answers), and marking the card
/// addressed wouldn't free the session, so Skip is left out.
struct CodeFormCard: View {
    let form: PendingForm
    let card: String
    let store: Store
    @Bindable var model: RouterModel
    @State private var page = 0
    /// Questions whose "Other" is chosen with nothing typed yet (typing keeps it chosen).
    @State private var otherOpen: Set<String> = []
    @FocusState private var otherFocus: String?

    var body: some View {
        if let answers = model.delivered[form.id], model.sent.contains(form.id) {
            QuestionReceipt(questions: form.questions, answers: answers)
        } else {
            question
        }
    }

    private var question: some View {
        let count = form.questions.count
        let index = min(page, max(0, count - 1))
        let q = form.questions[index]
        let locked = model.locked(form)
        let last = index == count - 1
        let busy = model.sending.contains(form.id)
        let ready = last ? model.answers(form) != nil : answered(q)
        let A = CDS.Approval.self
        return VStack(alignment: .leading, spacing: 0) {
            // Header: the question, and the pager when there are several.
            HStack(alignment: .center, spacing: A.pad.md) {
                Text(RouterText.inline(q.question))
                    .cdsBlock(CDS.Density.comfortable.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if count > 1 {
                    HStack(spacing: A.pad.xs) {
                        ClaudeButton(icon: "chevron.left", label: "Previous question", variant: .ghost, size: .sm) {
                            page = index - 1
                        }
                        .disabled(index == 0 || busy)
                        Text("\(index + 1) of \(count)")
                            .cdsBlock(CDS.Density.comfortable.caption, color: CDS.Text.muted)
                            .monospacedDigit()
                        ClaudeButton(icon: "chevron.right", label: "Next question", variant: .ghost, size: .sm) {
                            page = index + 1
                        }
                        .disabled(last || busy)
                    }
                    .padding(.vertical, -A.pad.xs).padding(.trailing, -A.pad.sm)
                }
            }
            .padding(.vertical, A.pad.md).padding(.horizontal, A.pad.lg)
            .background(CDS.Fill.neutral)

            // Options, then Other, a 1px line between consecutive rows.
            VStack(spacing: 0) {
                ForEach(Array(q.options.enumerated()), id: \.element.label) { n, option in
                    if n > 0 { AnswerSeparator() }
                    OptionRow(number: n + 1, label: option.label, detail: option.description,
                              on: model.picked(form, q).contains(option.label), multi: q.multiSelect) {
                        if !q.multiSelect { otherOpen.remove(key(q)) }
                        model.pick(option.label, in: q, of: form)
                    }
                    .disabled(locked)
                }
                if !q.options.isEmpty { AnswerSeparator() }
                otherRow(q, locked: locked)
            }

            // Footer: Next, or Submit on the last page, with ⌘⏎.
            HStack(spacing: A.gap.sm) {
                if let error = model.formErrors[form.id] {
                    Text(error).cdsBlock(CDS.Density.comfortable.caption, color: CDS.Text.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ClaudeButton(last ? "Submit" : "Next", variant: .primary, shortcut: ["cmd", "enter"], busy: busy) {
                    if last { model.sendAnswer(form, card: card, store: store) } else { page = index + 1 }
                }
                .disabled(!ready || locked)
                .keyboardShortcut(.return, modifiers: .command)
                .help(ready ? "" : last && answered(q) ? "Question \(firstUnanswered + 1) is unanswered"
                                                       : "Choose an option")
            }
            .padding(.top, A.pad.md).padding(.horizontal, A.pad.lg).padding(.bottom, A.pad.lg)
        }
        .frame(maxWidth: A.maxWidth, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: A.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: A.radius, style: .continuous).inset(by: -0.5).stroke(CDS.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(q.header.isEmpty ? "Question" : q.header)
    }

    /// Claude's "Other" row: the mark and "Other" over a full-row button; chosen, a field under the label.
    private func otherRow(_ q: PendingForm.Question, locked: Bool) -> some View {
        let k = key(q)
        let typed = model.otherText(form, q)
        let on = otherOpen.contains(k) || !typed.isEmpty
        let A = CDS.Approval.self
        return VStack(alignment: .leading, spacing: A.gap.sm) {
            HStack(alignment: .top, spacing: A.gap.md) {
                AnswerMark(on: on, multi: q.multiSelect)
                Text("Other").cdsBlock(CDS.Density.comfortable.body)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
            if on {
                CDSTextArea(placeholder: "Type your own answer here", lines: 1...4,
                            text: Binding(get: { model.otherText(form, q) }, set: { model.setOther($0, in: q, of: form) }))
                    .focused($otherFocus, equals: k)
                    .padding(.leading, CDS.Approval.mark + A.gap.md)
                    .accessibilityLabel("Other answer to \(q.question)")
            }
        }
        .padding(A.pad.lg)
        .background {
            Button {
                if on {
                    otherOpen.remove(k)
                    model.setOther("", in: q, of: form)
                } else {
                    // One choice: "Other" replaces the option picked.
                    if !q.multiSelect, let current = model.picked(form, q).first { model.pick(current, in: q, of: form) }
                    otherOpen.insert(k)
                    otherFocus = k
                }
            } label: { Color.clear.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel("Other")
            .accessibilityAddTraits(on ? .isSelected : [])
        }
        .disabled(locked)
    }

    private func key(_ q: PendingForm.Question) -> String { "\(form.id)|\(q.question)" }

    private func answered(_ q: PendingForm.Question) -> Bool {
        !model.picked(form, q).isEmpty || !model.otherText(form, q).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var firstUnanswered: Int { form.questions.firstIndex { !answered($0) } ?? 0 }
}

/// The receipt Claude leaves once a question is answered: each question (medium) and its answer, 1px lines between.
private struct QuestionReceipt: View {
    let questions: [PendingForm.Question]
    let answers: [String: String]

    var body: some View {
        let A = CDS.Approval.self
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(questions.enumerated()), id: \.element.question) { i, q in
                if i > 0 { AnswerSeparator() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(RouterText.inline(q.question)).cdsBlock(CDS.Density.comfortable.body, .medium)
                    Text(answers[q.question] ?? "").cdsBlock(CDS.Density.comfortable.body, color: CDS.Text.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, A.pad.md).padding(.horizontal, A.pad.lg)
                .accessibilityElement(children: .combine)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: A.maxWidth, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: A.receiptRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: A.receiptRadius, style: .continuous).inset(by: -0.5).stroke(CDS.border, lineWidth: 1))
        .transition(.opacity.animation(.easeOut(duration: 0.2)))
    }
}

/// `.epitaxy-answer-option + .epitaxy-answer-option { border-top: 1px solid var(--cds-border) }`.
private struct AnswerSeparator: View {
    var body: some View { Rectangle().fill(CDS.border).frame(height: 1) }
}

/// One answer row (`.epitaxy-answer-option`): 16 all round, the mark 16 from the label, the description under it. No
/// hover fill, as Claude's.
struct OptionRow: View {
    let number: Int
    let label: String
    let detail: String
    let on: Bool
    var multi = false
    let action: () -> Void

    var body: some View {
        let A = CDS.Approval.self
        Button(action: action) {
            HStack(alignment: .top, spacing: A.gap.md) {
                AnswerMark(on: on, multi: multi)
                VStack(alignment: .leading, spacing: A.gap.xs) {
                    Text(RouterText.inline(label)).cdsBlock(CDS.Density.comfortable.body)
                    if !detail.isEmpty {
                        Text(RouterText.inline(detail)).cdsBlock(CDS.Density.comfortable.body, color: CDS.Text.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(A.pad.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detail.isEmpty ? label : "\(label), \(detail)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint("Option \(number)")
    }
}

/// The question card's 20pt mark: `.epitaxy-radio-mark` (white-20% ring; chosen, accent with a 10pt white dot) or, for
/// several choices, CDS Checkbox (radius 5, a bold 16pt check).
private struct AnswerMark: View {
    let on: Bool
    let multi: Bool

    var body: some View {
        let size = CDS.Approval.mark
        Group {
            if multi {
                ZStack {
                    RoundedRectangle(cornerRadius: CDS.Approval.checkboxRadius, style: .continuous)
                        .fill(on ? CDS.Fill.accent : .clear)
                    RoundedRectangle(cornerRadius: CDS.Approval.checkboxRadius, style: .continuous)
                        .strokeBorder(on ? .clear : CDS.borderStrong, lineWidth: 1)
                    if on {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                }
            } else {
                ZStack {
                    Circle().fill(on ? CDS.Fill.accent : .clear)
                    if on { Circle().fill(.white).frame(width: size - 10, height: size - 10) }
                    else { Circle().strokeBorder(CDS.borderStrong, lineWidth: 1) }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Plans

/// A plan to approve as Claude's plan card (§2) in the card shell (§3): "Claude proposed a plan", then Revise… (Esc) and
/// Accept (⌘⏎); Revise… opens Claude's revise mode, a feedback field with Back and Revise. Claude opens the plan in a
/// viewer; Lookout has none, so the plan shows in the card, under its header.
///
/// Claude also offers Reject and a second, permission-mode Accept ("Accept and allow edits"): Lookout's hook takes
/// approve or keep planning only, so there is one "Accept" (Claude's label when there's no mode to pick) and no Reject.
struct CodePlanCard: View {
    let form: PendingForm
    let card: String
    let store: Store
    @Bindable var model: RouterModel
    @FocusState private var noteFocused: Bool
    /// In the model, not the view: the window's keys see it, so Esc is Back before it is anything else (`RouterKeys`).
    private var revising: Bool { model.revisingPlan == form.id }

    var body: some View {
        let A = CDS.Approval.self
        let locked = model.locked(form)
        let busy = model.sending.contains(form.id)
        let decided = model.sent.contains(form.id) ? model.planDecided[form.id] : nil
        VStack(alignment: .leading, spacing: A.gap.sm) {
            // Body (gap 12): the header, the plan, the feedback field in revise mode.
            HStack(alignment: .center, spacing: 4) {
                Text("Claude proposed a plan").cdsBlock(CDS.Density.comfortable.body, .semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: A.headerMinHeight)
            Text(RouterText.plan(form.plan ?? ""))
                .cdsBlock(CDS.Density.comfortable.body, color: CDS.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let decided {
                decision(decided)
            } else {
                if revising {
                    CDSTextArea(placeholder: "What should change? (optional)", lines: 3...3,
                                text: Binding(get: { model.planNote(form) }, set: { model.setPlanNote($0, of: form) }),
                                onSubmit: { revise() })
                        .focused($noteFocused)
                        .disabled(locked)
                        .accessibilityLabel("Plan feedback")
                }
                if let error = model.formErrors[form.id] {
                    Text(error).cdsBlock(CDS.Density.comfortable.caption, color: CDS.Text.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions(locked: locked, busy: busy)
                    .padding(.top, A.gap.sm) // the shell's own gap between body and actions
            }
        }
        .padding(A.pad.lg)
        .frame(maxWidth: A.maxWidth, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: A.radius, style: .continuous).inset(by: -0.5).stroke(CDS.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude proposed a plan")
        // Revise mode opened by Esc as by Revise…: the feedback field has the keyboard.
        .onChange(of: revising) { _, now in if now { noteFocused = true } }
    }

    /// The actions row: Revise… on the left; Accept on the right. In revise mode: Back, then Revise.
    @ViewBuilder
    private func actions(locked: Bool, busy: Bool) -> some View {
        HStack(spacing: 4) {
            if revising {
                // Esc too, through the window's keys (`RouterKeys`), which have it first.
                ClaudeButton("Back") { model.revisingPlan = nil }
                Spacer(minLength: 0)
                ClaudeButton("Revise", variant: .primary, busy: busy) { revise() }
            } else {
                ClaudeButton("Revise…", shortcut: ["esc"]) {
                    model.revisingPlan = form.id
                    noteFocused = true
                }
                Spacer(minLength: 0)
                ClaudeButton("Accept", variant: .primary, shortcut: ["cmd", "enter"], busy: busy) {
                    model.decidePlan(form, approve: true, card: card, store: store)
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .disabled(locked)
    }

    private func revise() {
        model.decidePlan(form, approve: false, card: card, store: store)
    }

    /// Decided: what was sent, as the question receipt's answer line.
    private func decision(_ d: PendingForm.PlanDecision) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(d.approve ? "Accepted" : "Sent back to keep planning").cdsBlock(CDS.Density.comfortable.body, .medium)
            if !d.approve, !d.feedback.isEmpty {
                Text(d.feedback).cdsBlock(CDS.Density.comfortable.body, color: CDS.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, CDS.Approval.gap.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(CDS.border).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Fields

/// CDS TextArea (§5.7): white-5% fill, a 1px white-10% ring (20% on hover), radius 8, 8 × 12, text 14/20, muted placeholder.
struct CDSTextArea: View {
    let placeholder: String
    let lines: ClosedRange<Int>
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let D = CDS.Density.comfortable
        let shape = RoundedRectangle(cornerRadius: D.radius, style: .continuous)
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(CDS.Text.muted), axis: .vertical)
            .textFieldStyle(.plain)
            .cdsBlock(D.body)
            .lineLimit(lines)
            .onSubmit(onSubmit)
            .padding(.vertical, D.pad.sm).padding(.horizontal, D.pad.md)
            .background(shape.fill(CDS.Fill.field))
            .overlay(shape.strokeBorder(hovered && enabled ? CDS.borderStrong : CDS.border, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovered = $0 }
    }
}

// MARK: - Button

/// CDS Button (§4): a paint layer under the label (inset 0.5 for primary and danger), which alone squishes to 0.975 on
/// press and springs back; hover fills; disabled at 40%. Shortcuts show as keycaps 8 after the label, 7 from the edge.
struct ClaudeButton: View {
    enum Variant { case primary, secondary, ghost, danger }

    enum Size {
        case sm, base
        var height: CGFloat { self == .sm ? 28 : 32 }
        var padding: CGFloat { self == .sm ? 10 : 12 }
        var radius: CGFloat { self == .sm ? 7 : 8 }
    }

    let title: String
    var variant: Variant
    var size: Size
    var icon: String?
    var iconOnly = false
    var shortcut: [String]
    var busy: Bool
    let action: () -> Void

    init(_ title: String, primary: Bool = false, variant: Variant? = nil, size: Size = .base, icon: String? = nil,
         shortcut: [String] = [], busy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.variant = variant ?? (primary ? .primary : .secondary)
        self.size = size
        self.icon = icon
        self.shortcut = shortcut
        self.busy = busy
        self.action = action
    }

    /// Icon only: square at the size's height, the label read out (and shown as the tooltip).
    init(icon: String, label: String, variant: Variant = .ghost, size: Size = .base, action: @escaping () -> Void) {
        self.init(label, variant: variant, size: size, icon: icon, action: action)
        iconOnly = true
    }

    var body: some View {
        Button(action: action) {
            content.opacity(busy ? 0 : 1)
                .overlay { if busy { FjordLoader(color: ink).frame(width: 14, height: 14) } }
        }
        .buttonStyle(CDSButtonStyle(variant: variant, size: size, iconOnly: iconOnly))
        .allowsHitTesting(!busy)
        .accessibilityLabel(title)
        .help(iconOnly ? title : "")
    }

    private var ink: Color {
        switch variant {
        case .primary: CDS.Text.onPrimary
        case .danger: .white
        case .secondary, .ghost: CDS.Text.primary
        }
    }

    @ViewBuilder private var content: some View {
        if iconOnly, let icon {
            ButtonIcon(name: icon, size: 13).foregroundStyle(ink)
        } else {
            let weight: CDS.Weight = variant == .primary || variant == .danger ? .medium : .regular
            HStack(spacing: 4) {
                if let icon {
                    ButtonIcon(name: icon, size: 13).padding(.leading, -4)
                }
                Text(title).cdsText(CDS.Density.comfortable.body, weight, ink).lineLimit(1)
                if !shortcut.isEmpty {
                    CDSShortcut(keys: shortcut, ink: variant == .primary || variant == .danger ? ink : CDS.Keycap.ink)
                        .padding(.leading, 4)
                        // `me-[calc((h − 1em − 6px)/2 − pad)]`: the keycap as far from the right as from the top.
                        .padding(.trailing, (size.height - 18) / 2 - size.padding)
                }
            }
            .foregroundStyle(ink)
        }
    }
}

private struct CDSButtonStyle: ButtonStyle {
    let variant: ClaudeButton.Variant
    let size: ClaudeButton.Size
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, variant: variant, size: size, iconOnly: iconOnly)
    }

    struct Styled: View {
        let configuration: Configuration
        let variant: ClaudeButton.Variant
        let size: ClaudeButton.Size
        let iconOnly: Bool
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let pressed = configuration.isPressed && enabled
            let solid = variant == .primary || variant == .danger
            let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
            configuration.label
                .padding(.horizontal, iconOnly ? 0 : size.padding)
                .frame(width: iconOnly ? size.height : nil, height: size.height)
                .background {
                    shape.fill(fill(hovered && enabled))
                        .bakedShadow(variant == .secondary ? CDS.fieldShadow : .clear, .rounded(size.radius), radius: 1, y: 1,
                                     fill: fill(hovered && enabled))
                        .padding(solid ? 0.5 : 0)
                        .scaleEffect(pressed ? 0.975 : 1)
                        .motion(pressed ? .easeOut(duration: 0.06) : .spring(duration: 0.45, bounce: 0.35), value: pressed)
                        .motion(.easeOut(duration: 0.06), value: hovered)
                }
                .contentShape(shape)
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovered = $0 }
        }

        private func fill(_ hot: Bool) -> Color {
            switch variant {
            case .primary: hot ? CDS.Fill.primaryHover : CDS.Fill.primary
            case .secondary: hot ? CDS.Fill.secondaryHover : CDS.Fill.secondary
            case .ghost: hot ? CDS.Fill.ghostHover : .clear
            case .danger: hot ? CDS.Fill.dangerHover : CDS.Fill.danger
            }
        }
    }
}

/// CDS Shortcut (§4.6): one 18pt keycap per key, 2 apart, modifiers ordered ctrl, alt, shift, cmd; caption text, a 1px
/// border at 22% of the ink, radius 4.
struct CDSShortcut: View {
    let keys: [String]
    var ink: Color = CDS.Keycap.ink

    private static let order = ["ctrl", "alt", "shift", "cmd"]
    private static let glyphs = ["cmd": "⌘", "shift": "⇧", "alt": "⌥", "ctrl": "⌃", "enter": "⏎", "esc": "Esc",
                                 "tab": "⇥", "space": "␣", "backspace": "⌫", "left": "←", "up": "↑", "right": "→", "down": "↓"]

    var body: some View {
        let mods = keys.filter { Self.order.contains($0) }.sorted { Self.order.firstIndex(of: $0)! < Self.order.firstIndex(of: $1)! }
        let rest = keys.filter { !Self.order.contains($0) }
        HStack(spacing: 2) {
            ForEach(Array((mods + rest).enumerated()), id: \.offset) { _, key in
                let glyph = Self.glyphs[key] ?? key.uppercased()
                Text(glyph)
                    .font(glyph.count > 1 ? CDS.sans(12) : .system(size: 12))
                    .foregroundStyle(ink)
                    .padding(.horizontal, glyph.count > 1 ? 3 : 0)
                    .frame(minWidth: CDS.Keycap.size, minHeight: CDS.Keycap.size, maxHeight: CDS.Keycap.size)
                    .overlay(RoundedRectangle(cornerRadius: CDS.Keycap.radius, style: .continuous)
                        .strokeBorder(ink.opacity(0.22), lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Type

private extension View {
    /// A CDS text role laid out as CSS does: line spacing between lines, and half the leading over and under, so one line
    /// is the role's full line height.
    func cdsBlock(_ role: (CGFloat, CGFloat), _ weight: CDS.Weight = .regular, color: Color = CDS.Text.primary) -> some View {
        let font = CDS.nsSans(role.0, weight)
        let natural = font.ascender - font.descender + font.leading
        return cdsText(role, weight, color).padding(.vertical, max(0, role.1 - natural) / 2)
    }
}
