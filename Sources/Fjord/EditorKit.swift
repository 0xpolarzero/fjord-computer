import SwiftUI

// The category editor's parts: a wrapping layout for sentences, chips, the value slot (tokens + an autocomplete popover),
// and the lists those popovers offer. Everything is CDS: chips are 24 tall, radius 6, white 10%; red when impossible.

private let body13: (CGFloat, CGFloat) = (13, 19)
private let foot12: (CGFloat, CGFloat) = (12, 16)

// MARK: - Flow layout

/// Children left to right, wrapping to the next line at the proposed width; each line is centred on its tallest child.
struct SentenceLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 6

    struct Line {
        var items: [(index: Int, x: CGFloat, size: CGSize)] = []
        var y: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = lines.map { $0.items.last.map { $0.x + $0.size.width } ?? 0 }.max() ?? 0
        return CGSize(width: width, height: lines.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for line in arrange(width: bounds.width, subviews: subviews) {
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + line.y + (line.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size))
            }
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = [Line()]
        var x: CGFloat = 0
        var y: CGFloat = 0
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0, x + size.width > width {
                lines[lines.count - 1].y = y
                y += lines[lines.count - 1].height + lineSpacing
                lines.append(Line())
                x = 0
            }
            lines[lines.count - 1].items.append((index, x, size))
            lines[lines.count - 1].height = max(lines[lines.count - 1].height, size.height)
            x += size.width + spacing
        }
        lines[lines.count - 1].y = y
        return lines.filter { !$0.items.isEmpty }
    }
}

// MARK: - Chips

enum ChipTone { case neutral, danger, accent, dashed }

/// The chip's surface: 24 tall, 8 in, radius 6; hover lifts the fill. Danger and accent use CDS's tinted badges.
struct ChipLook: ViewModifier {
    var tone: ChipTone = .neutral
    var hot = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        content
            .font(CDS.sans(body13.0, .regular))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(ring, style: StrokeStyle(lineWidth: 1, dash: tone == .dashed ? [3, 2] : [])))
            .contentShape(shape)
    }

    private var ink: Color {
        switch tone {
        case .neutral: CDS.Text.primary
        case .danger: CDS.BadgeTint.dangerText
        case .accent: CDS.BadgeTint.accentText
        case .dashed: hot ? CDS.Text.primary : CDS.Text.muted
        }
    }

    private var fill: Color {
        switch tone {
        case .neutral: hot ? CDS.Fill.secondaryHover : CDS.Fill.secondary
        case .danger: CDS.BadgeTint.dangerFill
        case .accent: CDS.BadgeTint.accentFill
        case .dashed: hot ? CDS.Fill.ghostHover : .clear
        }
    }

    private var ring: Color {
        switch tone {
        case .danger: CDS.Fill.danger.opacity(0.7)
        case .dashed: hot ? CDS.borderStrong : CDS.borderStrong.opacity(0.6)
        default: .clear
        }
    }
}

struct ChipButtonStyle: ButtonStyle {
    var tone: ChipTone = .neutral

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, tone: tone)
    }

    private struct Styled: View {
        let configuration: Configuration
        let tone: ChipTone
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .modifier(ChipLook(tone: tone, hot: (hovering || configuration.isPressed) && enabled))
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

/// A chip that is a menu: its value and a small caret.
struct MenuChip<Items: View>: View {
    let title: String
    var tone: ChipTone = .neutral
    var label: String?
    @ViewBuilder var items: () -> Items

    var body: some View {
        Menu { items() } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(CDS.Text.muted)
            }
        }
        .menuStyle(.button)
        .buttonStyle(ChipButtonStyle(tone: tone))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(label ?? title)
    }
}

/// A word of the sentence that is also a menu (to, by, in): muted, primary on hover.
struct WordMenu<Items: View>: View {
    let text: String
    var tone: ChipTone = .neutral
    @ViewBuilder var items: () -> Items
    @State private var hovering = false

    var body: some View {
        Menu { items() } label: {
            Text(text).cdsText(body13, .regular, tone == .danger ? CDS.Text.danger : hovering ? CDS.Text.primary : CDS.Text.muted)
                .padding(.horizontal, 2).frame(height: 24).contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .accessibilityLabel(text)
    }
}

/// A plain word of the sentence.
struct Word: View {
    let text: String
    var tone: ChipTone = .neutral
    init(_ text: String, tone: ChipTone = .neutral) { self.text = text; self.tone = tone }

    var body: some View {
        Text(text).cdsText(body13, .regular, tone == .danger ? CDS.Text.danger : CDS.Text.muted).lineLimit(1)
            .padding(.horizontal, 2).frame(height: 24)
    }
}

/// A chosen value: a chip with its remove button.
struct ValueToken: View {
    let title: String
    var symbol: String?
    var tone: ChipTone = .neutral
    var dim = false
    /// Clicking the chip itself (not its ×).
    var onTap: (() -> Void)?
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(CDS.Text.muted)
                }
                Text(title)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hovering ? CDS.Text.primary : CDS.Text.muted)
                    .frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(title)")
        }
        .modifier(ChipLook(tone: tone))
        .opacity(dim ? 0.7 : 1)
        .onHover { hovering = $0 }
    }
}

// MARK: - Slot field

struct SlotOption<V: Hashable>: Identifiable {
    var title: String
    var detail: String?
    var symbol: String?
    var value: V
    var tip: String?
    var id: String { title + "|" + String(describing: value) }
}

/// A row of the popover that toggles something on the slot (to: the roles).
struct SlotToggle: Identifiable {
    let title: String
    let isOn: Bool
    let apply: (Bool) -> Void
    var id: String { title }
}

/// The word that names a slot (by, in, on, named, to) and what it does: it is the chip that opens the slot's autocomplete,
/// its popover holds `roles` on top and a "Remove <name>" action in the footer. Set on the slot view with `.slotWord(_:)`.
struct SlotWord {
    var name: String
    /// What the word shows, when it differs from the name ("to (assigned)").
    var text: String
    var tone: ChipTone = .neutral
    var roles: [SlotToggle] = []
    var remove: (() -> Void)?
}

private struct SlotWordKey: EnvironmentKey {
    static let defaultValue: SlotWord? = nil
}

extension EnvironmentValues {
    var slotWord: SlotWord? {
        get { self[SlotWordKey.self] }
        set { self[SlotWordKey.self] = newValue }
    }
}

extension View {
    func slotWord(_ word: SlotWord) -> some View { environment(\.slotWord, word) }
}

/// The scope word as a button: muted, primary on hover, red when impossible.
private struct WordButton: View {
    let text: String
    var tone: ChipTone = .neutral
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text).cdsText(body13, .regular, tone == .danger ? CDS.Text.danger : hovering ? CDS.Text.primary : CDS.Text.muted)
                .padding(.horizontal, 2).frame(height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .accessibilityLabel(text)
    }
}

/// The small trailing + of a slot with values: muted, primary on hover.
private struct AddValueGlyph: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hovering ? CDS.Text.primary : CDS.Text.muted)
                .opacity(hovering ? 1 : 0.55)
                .frame(width: 18, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Add another value")
    }
}

/// The values of a slot: its tokens, `except` ones after the word, and the chip that opens the autocomplete.
/// Several direct children, so it flows with the sentence. A slot with a `SlotWord` opens its autocomplete from the word.
struct SlotField<V: Codable & Hashable>: View {
    @Binding var pick: Pick<V>
    var placeholder: String
    var tone: ChipTone = .neutral
    var allowsExcept = true
    var title: (V) -> String
    var symbol: (V) -> String? = { _ in nil }
    var isBroken: (V) -> Bool = { _ in false }
    /// Rows for what is typed (and whether the pick is an exception).
    var options: (String, Pick<V>) -> [SlotOption<V>]
    var parse: (String) -> V?
    /// Plain values that a group can hold, and how to make one from them.
    var groupable = 0
    var saveGroup: ((String) -> Void)?
    var groupNoun = "values"
    @State private var open = false
    @Environment(\.slotWord) private var word

    var body: some View {
        let empty = pick.include.isEmpty && pick.except.isEmpty
        Group {
            if let word {
                WordButton(text: word.text, tone: word.tone) { open = true }
                    .popover(isPresented: $open, arrowEdge: .bottom) { popover }
            }
            if empty {
                // Nothing picked: a dim placeholder chip says what the slot is and opens the autocomplete.
                Button { open = true } label: { Text(placeholder) }
                    .buttonStyle(ChipButtonStyle(tone: tone == .danger ? .danger : .dashed))
                    .accessibilityLabel("Choose \(placeholder)")
                    .popover(isPresented: anchor(word == nil), arrowEdge: .bottom) { popover }
            }
            ForEach(pick.include, id: \.self) { value in token(value, dim: false) }
            if !pick.include.isEmpty {
                // A quiet + after the last chip: another value, whether or not the slot has a word.
                AddValueGlyph { open = true }
                    .popover(isPresented: anchor(word == nil), arrowEdge: .bottom) { popover }
            }
            if !pick.except.isEmpty {
                Word(pick.include.isEmpty ? placeholder + " except" : "except")
                    .contentShape(Rectangle()).onTapGesture { open = true }
                ForEach(Array(pick.except.enumerated()), id: \.element) { i, value in
                    token(value, dim: true)
                        .popover(isPresented: anchor(word == nil && pick.include.isEmpty && i == 0), arrowEdge: .bottom) { popover }
                }
            }
        }
    }

    /// One anchor shows the popover: the word when the slot has one, else the first chip.
    private func anchor(_ on: Bool) -> Binding<Bool> {
        Binding(get: { open && on }, set: { open = $0 })
    }

    private func token(_ value: V, dim: Bool) -> some View {
        ValueToken(title: title(value), symbol: symbol(value), tone: isBroken(value) ? .danger : tone, dim: dim, onTap: { open = true }) {
            if dim { pick.except.removeAll { $0 == value } } else { pick.include.removeAll { $0 == value } }
        }
    }

    private var removal: (String, () -> Void)? {
        guard let word, let remove = word.remove else { return nil }
        return ("Remove \(word.name)", remove)
    }

    private var popover: some View {
        SlotPopover(pick: pick, allowsExcept: allowsExcept, title: title, symbol: symbol, options: options, parse: parse,
                    groupable: groupable, groupNoun: groupNoun, onPick: { value, excepting in
            if excepting {
                pick.include.removeAll { $0 == value }
                if !pick.except.contains(value) { pick.except.append(value) }
            } else {
                pick.except.removeAll { $0 == value }
                if !pick.include.contains(value) { pick.include.append(value) }
            }
        }, onSaveGroup: saveGroup.map { save in { name in save(name); open = false } },
                    roles: word?.roles ?? [], removal: removal)
    }
}

/// The autocomplete: a field, the rows it filters (↑↓ and Return pick), and the footer actions.
struct SlotPopover<V: Codable & Hashable>: View {
    let pick: Pick<V>
    let allowsExcept: Bool
    let title: (V) -> String
    let symbol: (V) -> String?
    let options: (String, Pick<V>) -> [SlotOption<V>]
    let parse: (String) -> V?
    let groupable: Int
    let groupNoun: String
    let onPick: (V, Bool) -> Void
    let onSaveGroup: ((String) -> Void)?
    /// Esc in the search closes the picker.
    @Environment(\.dismiss) private var dismiss
    /// A slot's word: its toggles go on top, and its "Remove <word>" action in the footer.
    var roles: [SlotToggle] = []
    var removal: (String, () -> Void)?
    @State private var query = ""
    @State private var excepting = false
    @State private var index = 0
    @State private var naming = false
    @State private var groupName = ""
    @FocusState private var focused: Bool

    /// What the field filters to, then what was typed as a value of its own ("as typed") after those: Return takes the
    /// highlighted match first, and the typed value when nothing matches.
    private var rows: [SlotOption<V>] {
        var rows = options(query, pick)
        let typed = query.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty, let value = parse(typed), !rows.contains(where: { $0.value == value }),
           !pick.include.contains(value), !pick.except.contains(value) {
            rows.append(SlotOption(title: title(value), detail: nil, symbol: symbol(value), value: value))
        }
        return rows
    }

    /// A pick keeps the popover open for the next one: the search is cleared, and the picked value is off the list.
    private func choose(_ value: V) {
        onPick(value, excepting)
        query = ""
        index = 0
        focused = true
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            if !roles.isEmpty {
                VStack(spacing: 0) {
                    ForEach(roles) { role in
                        Button { role.apply(!role.isOn) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: role.isOn ? "checkmark" : "circle")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(role.isOn ? CDS.Text.primary : CDS.Text.muted).frame(width: 14)
                                Text(role.title).cdsText(body13, .regular, role.isOn ? CDS.Text.primary : CDS.Text.secondary).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).frame(height: 26).contentShape(Rectangle())
                        }
                        .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: 6, style: .continuous), rest: .clear,
                                                          hover: CDS.Fill.ghostHover, pressed: CDS.Fill.ghostSelected))
                    }
                }
                .padding(4)
                Rectangle().fill(CDS.Settings.divider).frame(height: 1)
            }
            HStack(spacing: 6) {
                if excepting {
                    Text("except").cdsText(foot12, .medium, CDS.BadgeTint.dangerText)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(CDS.BadgeTint.dangerFill))
                }
                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(CDS.sans(13))
                    .focused($focused)
                    .cdsPlaceholder(excepting ? "Not these…" : "Search or type…", shown: query.isEmpty)
                    .onSubmit { commit(rows) }
                    .onExitCommand { dismiss() }
                    .onKeyPress(.downArrow) { index = min(index + 1, max(rows.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .accessibilityLabel("Search values")
            }
            .padding(.horizontal, 10).frame(height: 34)
            Rectangle().fill(CDS.Settings.divider).frame(height: 1)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        Button { choose(row.value) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: row.symbol ?? "circle.fill")
                                    .font(.system(size: row.symbol == nil ? 3 : 11)).foregroundStyle(CDS.Text.muted)
                                    .frame(width: 14)
                                Text(row.title).cdsText(body13).lineLimit(1)
                                Spacer(minLength: 8)
                                if let detail = row.detail { Text(detail).cdsText(foot12, .regular, CDS.Text.muted).lineLimit(1) }
                            }
                            .padding(.horizontal, 8).frame(height: 26).contentShape(Rectangle())
                        }
                        .tip(row.title, row.tip)
                        .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: 6, style: .continuous), rest: i == index ? CDS.Fill.ghostHover : .clear,
                                                          hover: CDS.Fill.ghostHover, pressed: CDS.Fill.ghostSelected))
                    }
                    if rows.isEmpty {
                        Text("Nothing matches").cdsText(foot12, .regular, CDS.Text.muted).frame(maxWidth: .infinity, minHeight: 26)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 26 * 8 + 8)
            .fixedSize(horizontal: false, vertical: true)
            if allowsExcept || removal != nil || (onSaveGroup != nil && groupable >= 2) {
                Rectangle().fill(CDS.Settings.divider).frame(height: 1)
                footer
            }
        }
        .frame(width: 300)
        .background(CDS.Surface.s3)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in index = 0 }
    }

    @ViewBuilder private var footer: some View {
        if naming {
            HStack(spacing: 6) {
                TextField("", text: $groupName)
                    .textFieldStyle(.plain).font(CDS.sans(13))
                    .cdsPlaceholder("Group name", shown: groupName.isEmpty)
                    .onSubmit { saveGroup() }
                    .accessibilityLabel("Group name")
                Button("Save") { saveGroup() }
                    .buttonStyle(SettingsButtonStyle(size: .xxs))
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 10).frame(height: 34)
        } else {
            // One line when the popover is wide enough; the group action drops to its own line when it isn't.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    footerActions
                    Spacer(minLength: 0)
                    groupAction
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) { footerActions; Spacer(minLength: 0) }
                    HStack(spacing: 4) { Spacer(minLength: 0); groupAction }
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .frame(minHeight: 30)
        }
    }

    /// Except…, and the slot's Remove, on the left of the footer.
    @ViewBuilder private var footerActions: some View {
        if allowsExcept {
            Button { excepting.toggle(); index = 0; focused = true } label: {
                Text(excepting ? "Include instead" : "Except…")
            }
            .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .xxs))
        }
        if let removal {
            Button(removal.0, action: removal.1)
                .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .xxs))
        }
    }

    @ViewBuilder private var groupAction: some View {
        if onSaveGroup != nil, groupable >= 2 {
            Button { naming = true } label: { Text("Save \(groupable) \(groupNoun) as group…") }
                .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .xxs))
                .fixedSize()
        }
    }

    private func commit(_ rows: [SlotOption<V>]) {
        // Never a silent dismissal: nothing to pick means the popover stays as it is.
        if rows.indices.contains(index) { choose(rows[index].value) }
    }

    private func saveGroup() {
        let name = groupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onSaveGroup?(name)
    }
}

// MARK: - Buttons and small controls

/// CDS's primary button (forms-buttons.md §4): white, dark text; 28 tall.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            configuration.label
                .font(CDS.sans(14, .medium))
                .foregroundStyle(CDS.Text.onPrimary)
                .padding(.horizontal, 12).frame(height: 28)
                .background(shape.fill(hovering || configuration.isPressed ? CDS.Fill.primaryHover : CDS.Fill.primary))
                .contentShape(shape)
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

/// A small ghost icon button (20 or 24) with a tooltip.
struct SmallIconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 24
    var tint: Color = CDS.Text.muted
    let action: () -> Void

    var body: some View {
        IconButton(symbol: symbol, help: label, label: label, size: size, tint: tint, action: action)
    }
}

extension CategoryColor {
    /// The category's tint on screen, from Claude's palette.
    var swatch: Color {
        switch self {
        case .clay: CDS.clay
        case .amber: CDS.Fill.warning
        case .green: CDS.BadgeTint.successText
        case .aqua: CDS.hex(0x4FC6C0)
        case .blue: CDS.Text.accent
        case .violet: CDS.BadgeTint.violetText
        case .magenta: CDS.hex(0xD66BB4)
        case .red: CDS.Text.danger
        case .gray: CDS.Text.muted
        }
    }

    var title: String { rawValue.capitalized }
}

/// A category's tile: its symbol in its colour on a faint tint of it.
struct CategoryTile: View {
    let symbol: String
    let color: CategoryColor
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size >= 32 ? 8 : 6, style: .continuous)
            .fill(color.swatch.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(color.swatch))
            .accessibilityHidden(true)
    }
}
