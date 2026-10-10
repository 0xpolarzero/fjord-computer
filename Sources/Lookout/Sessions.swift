import AppKit
import SwiftUI

// Session and inbox views shared by the hub: tiles, rows, actions, label editor, update button, and the
// menus / status lines the hub ports next (claude link, rate limit, session and inbox context menus).

/// A session's tile on the bar, as Claude would draw it: a neutral compact square (radius 6, white 10%) holding its two
/// letters (or emoji, or icon), and Claude's 6pt status dot as a badge in the corner: amber when it needs you, blue when it's
/// done and unread, grey and blinking while it works (or left something running). Picked: white 15% and a white 20% ring.
struct AgentTile: View {
    let row: AgentRow
    var size: CGFloat = CDS.Tile.size
    var selected = false

    var body: some View {
        let scale = size / CDS.Tile.size
        let shape = RoundedRectangle(cornerRadius: CDS.Tile.radius * scale, style: .continuous)
        let kind = ClaudeDot.Kind(row)
        AgentTileFace(row: row, size: size, selected: selected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.session.title)
            .spokenValue(of: row)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: CDS.Tile.radius * scale + 2, style: .continuous)
                        .strokeBorder(CDS.Tile.ring, lineWidth: 1.5).padding(-2.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if kind != .quiet {
                    let d = CDS.Tile.dot + 2 * CDS.Tile.dotGap
                    ClaudeDot(kind: kind)
                        .frame(width: d, height: d)
                        .background(Circle().fill(Color.black).frame(width: d, height: d))
                        .offset(x: d * 0.3, y: -d * 0.3)
                }
            }
            .contentShape(shape)
    }
}

/// The tile itself: its face on the neutral fill.
private struct AgentTileFace: View {
    let row: AgentRow
    var size: CGFloat
    var selected = false

    var body: some View {
        let scale = size / CDS.Tile.size
        let shape = RoundedRectangle(cornerRadius: CDS.Tile.radius * scale, style: .continuous)
        let emoji = row.label.unicodeScalars.first.map { $0.properties.isEmoji && $0.value > 0xFF } ?? false
        // What wants a look reads brighter; the rest sits back, as Claude's secondary text does.
        let lit = selected || row.group == .needsYou || row.group == .done
        Group {
            if let icon = row.icon {
                Image(systemName: icon)
                    .font(.system(size: CDS.Sidebar.symbol * scale, weight: .medium))
                    .symbolRenderingMode(.monochrome)
            } else {
                Text(row.label)
                    .font(emoji ? .system(size: size * 0.5) : CDS.sans(CDS.Tile.letters * scale, .medium))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
            .foregroundStyle(lit ? CDS.Text.primary : CDS.Text.secondary)
            .frame(width: size, height: size)
            .background(shape.fill(selected ? CDS.Tile.fillSelected : CDS.Tile.fill))
    }
}

extension ClaudeDot.Kind {
    /// A session's dot, as Claude's list draws it: needs you, done and unread, working (or left something running), else
    /// the quiet hollow ring.
    init(_ row: AgentRow) {
        switch row.group {
        case .needsYou: self = .needsYou
        case .done: self = .done
        case .working: self = .working
        case .pinned, .idle: self = .quiet
        }
    }
}

/// "Running swift test · 3m", ticking.
struct WorkingText: View {
    let row: AgentRow

    var body: some View {
        Ticking { now in
            Text(row.workingText(now: now)).foregroundStyle(row.waitsForYou ? CDS.Text.warning : CDS.Text.muted)
        }
    }
}

/// A session's value for VoiceOver, its age included, which moves on with the clock while a screen reader is on (nothing ticks
/// at rest for a bar nobody is listening to).
struct SpokenValue: ViewModifier {
    let row: AgentRow

    @ViewBuilder func body(content: Content) -> some View {
        if NSWorkspace.shared.isVoiceOverEnabled {
            Ticking(coarse: true) { now in content.accessibilityValue(row.spokenValue(now: now)) }
        } else {
            content.accessibilityValue(row.spokenValue())
        }
    }
}

extension View {
    func spokenValue(of row: AgentRow) -> some View { modifier(SpokenValue(row: row)) }
}

/// A project's colour dot and name.
struct ProjectLabel: View {
    let name: String
    let color: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let color {
                Circle().fill(color).frame(width: 6, height: 6)
            } else {
                Image(systemName: "text.bubble").font(.system(size: 9, weight: .medium))
            }
            Text(name)
        }
    }
}

/// One line per subagent or command still running, with what a subagent is on and how long it's been going.
struct TaskLines: View {
    let tasks: [ClaudeTask]

    var body: some View {
        Ticking { now in
            VStack(alignment: .leading, spacing: 3) {
                ForEach(tasks) { task in
                    HStack(spacing: 4) {
                        Image(systemName: task.kind == .agent ? "asterisk" : "terminal")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CDS.clay)
                            .frame(width: 12)
                        Text(task.title).foregroundStyle(CDS.Text.secondary).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(status(task, now: now))
                            .font(CDS.sans(CDS.RowControl.detail.0).monospacedDigit())
                            .foregroundStyle(CDS.Text.muted)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
            }
        }
        .font(CDS.sans(CDS.RowControl.detail.0))
    }

    private func status(_ task: ClaudeTask, now: Date) -> String {
        let elapsed = AgentRow.duration(now.timeIntervalSince(task.since))
        guard let activity = task.activity?.text else { return elapsed }
        return "\(activity) · \(elapsed)"
    }
}

/// Only kept sessions can be dragged; dropping on another kept one moves it there.
struct Reorderable: ViewModifier {
    let row: AgentRow
    let store: Store
    @Binding var dropTarget: Bool

    func body(content: Content) -> some View {
        if row.group != .pinned {
            content
        } else {
            content
                .draggable("agent:" + row.id) {
                    Text(row.session.title)
                        .font(CDS.sans(CDS.Sidebar.rowFont))
                        .padding(.horizontal, 8)
                        .frame(height: CDS.Sidebar.rowHeight)
                        .background(RoundedRectangle(cornerRadius: CDS.Sidebar.radius, style: .continuous).fill(CDS.Surface.s3))
                        .foregroundStyle(CDS.Text.primary)
                }
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first, id.hasPrefix("agent:") else { return false }
                    withAnimation(.spring(duration: 0.25)) { store.moveAgent(String(id.dropFirst(6)), onto: row.id) }
                    return true
                } isTargeted: { dropTarget = $0 }
        }
    }
}

/// Hover/selection actions, the same in the panel and the pill's drawer: Claude's row controls (§2.7), 24pt ghost
/// squares 2 apart, secondary glyphs that turn primary on a white 7.5% fill.
struct AgentActions: View {
    let row: AgentRow
    let store: Store
    /// Kept for the callers; Claude's controls are always 24.
    var size: CGFloat = CDS.RowControl.size
    /// The row already shows Keep and Remove: only read/unread and open here.
    var keepsInline = false

    var body: some View {
        HStack(spacing: CDS.RowControl.gap) {
            if !keepsInline {
                RowControl(symbol: row.entry.kept ? "pin.slash" : "pin", help: row.entry.kept ? "Unpin" : "Pin",
                           detail: (row.entry.kept ? "Leaves the list an hour after it goes quiet" : "Stays on the bar") + " · \(store.shortcut(.keepSession).display)") {
                    store.togglePin(row.id)
                }
            }
            if row.unread {
                RowControl(symbol: "checkmark", help: "Mark as read", detail: store.shortcut(.toggleRead).display) {
                    store.toggleAgentRead(row.id)
                }
            } else {
                RowControl(symbol: "circle.fill", help: "Mark as unread", detail: store.shortcut(.toggleRead).display, small: true) {
                    store.toggleAgentRead(row.id)
                }
            }
            if !keepsInline {
                RowControl(symbol: "xmark", help: "Hide", detail: "Until its next activity · \(store.shortcut(.removeSession).display)") {
                    store.dismissAgent(row.id)
                }
            }
            RowControl(symbol: "arrow.up.right", help: "Open in Claude", detail: store.shortcut(.openItem).display) {
                store.openAgent(row.id)
            }
        }
    }
}

/// One of Claude's row controls (`df-row-control`): 24 × 24, radius 6, a 13pt glyph (Claude's 16pt icon) in secondary, primary
/// on hover over white 7.5%.
private struct RowControl: View {
    let symbol: String
    let help: String
    var detail: String? = nil
    /// A glyph that is a dot, drawn smaller (Claude's unread mark).
    var small = false
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) { RowControlFace(symbol: symbol, small: small) }
            .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: CDS.Sidebar.radius, style: .continuous),
                                              rest: .clear, hover: CDS.Fill.ghostHover, pressed: CDS.Fill.ghostSelected))
            .focused($focused)
            .accessibilityLabel(help)
            .accessibilityHint(detail.flatMap { $0.isEmpty ? nil : $0 } ?? "")
            .tip(help, detail, focused: focused)
    }
}

private struct RowControlFace: View {
    let symbol: String
    let small: Bool
    @Environment(\.hoverFillHovering) private var hover

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: small ? 7 : CDS.Sidebar.symbol, weight: .medium))
            .foregroundStyle(hover ? CDS.Text.primary : CDS.Text.secondary)
            .frame(width: CDS.RowControl.size, height: CDS.RowControl.size)
    }
}

/// Two letters or an emoji; empty goes back to letters from the title.
struct LabelEditor: View {
    let row: AgentRow
    let store: Store
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Claude's compact popover content: 13/19 body, a 12/15 muted hint, a 24pt field and xs buttons, 12 around.
        VStack(alignment: .leading, spacing: 8) {
            Text("Label for \(row.session.title)").cdsText(CDS.Density.compact.body, .medium).lineLimit(1)
            HStack(spacing: 6) {
                TextField(row.label, text: $text)
                    .accessibilityLabel("Label for \(row.session.title)")
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .font(CDS.sans(CDS.Sidebar.rowFont))
                    .foregroundStyle(CDS.Text.primary)
                    .padding(.horizontal, 8)
                    .frame(width: 90, height: CDS.Density.compact.control)
                    .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous).fill(CDS.Fill.field))
                    .overlay(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                        .strokeBorder(focused ? CDS.borderStrong : CDS.border, lineWidth: 1))
                    .onSubmit(save)
                    .tip("Two letters or an emoji", "Empty goes back to the \(row.entry.icon != nil ? "icon" : "letters")")
                RowControl(symbol: "face.smiling", help: "Emoji") {
                    focused = true
                    NSApp.orderFrontCharacterPalette(nil)
                }
                Button("Save", action: save).buttonStyle(CompactButtonStyle())
            }
            if row.entry.label != nil {
                Button(row.entry.icon != nil ? "Use the picked icon" : "Use letters from the title") {
                    store.setAgentLabel(row.id, nil)
                    dismiss()
                }
                .buttonStyle(TextLinkStyle())
            }
            if store.canPickIcons && row.entry.label == nil {
                Button(row.entry.icon == nil ? "Pick an icon" : "Pick another icon") {
                    store.repickIcon(row.id)
                    dismiss()
                }
                .buttonStyle(TextLinkStyle())
            }
        }
        .padding(12)
        .frame(width: 240)
        .onAppear {
            text = row.entry.label ?? ""
            focused = true
        }
    }

    private func save() {
        store.setAgentLabel(row.id, text.isEmpty ? nil : text)
        dismiss()
    }
}

/// CDS Button, secondary, compact xs (forms-buttons.md §4): 24 tall, 8 across, radius 6, white 10% (14% on hover), 13pt
/// primary text; the paint squishes to .975 while pressed.
private struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }

    private struct Face: View {
        let configuration: Configuration
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(CDS.sans(CDS.Sidebar.rowFont))
                .foregroundStyle(CDS.Text.primary)
                .padding(.horizontal, CDS.Density.compact.pad.md)
                .frame(height: CDS.Density.compact.control)
                .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                    .fill(hovered ? CDS.Fill.secondaryHover : CDS.Fill.secondary)
                    .shadow(color: CDS.fieldShadow, radius: 1, y: 1)
                    .scaleEffect(configuration.isPressed ? 0.975 : 1))
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
        }
    }
}

/// CDS TextLink (forms-buttons.md §5.8): accent #6da7ec, underlined 3 below at 40%, full on hover; footnote size here.
private struct TextLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }

    private struct Face: View {
        let configuration: Configuration
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(CDS.sans(CDS.Density.compact.footnote.0))
                .foregroundStyle(CDS.Text.accent)
                .underline(true, color: CDS.Text.accent.opacity(hovered ? 1 : 0.4))
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }
    }
}

/// A new release, fetched in the background: an icon that says what it is on hover; click to restart into it
/// (or to download it, with a ring for progress, if that didn't happen on its own). Right-click for the release
/// notes or to skip that version; `UpdateMenu` beside it offers the same from the keyboard.
struct UpdateButton: View {
    let updater: Updater
    let horizontal: Bool
    @FocusState private var focused: Bool

    var body: some View {
        let version = updater.release?.version ?? ""
        Button { updater.advance() } label: { UpdateLabel(updater: updater, horizontal: horizontal, version: version) }
        // Claude's ghost chrome button: radius 6, white 7.5% on hover.
        .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: CDS.Sidebar.radius, style: .continuous),
                                          rest: .clear, hover: CDS.Fill.ghostHover, pressed: CDS.Fill.ghostSelected))
        .accessibilityLabel(Self.label(updater, version: version))
        .accessibilityHint(tooltip(version).0)
        .focused($focused)
        .tip(tooltip(version).0, tooltip(version).1, focused: focused)
        .contextMenu { UpdateActions(updater: updater) }
    }

    /// The tooltip: what it is, and what a click does.
    private func tooltip(_ version: String) -> (String, String?) {
        switch updater.phase {
        case .available: ("Lookout \(version) is available", "Click to download it · right-click for more")
        case .downloading: ("Downloading Lookout \(version)… \(Int(updater.fraction * 100))%", nil)
        case .ready: ("Lookout \(version) is ready", "Click to restart into it")
        case .installing: ("Installing Lookout \(version)…", nil)
        case .failed(let message): ("Update failed: \(message)", "Click to try again")
        case .idle: ("", nil)
        }
    }

    fileprivate static func label(_ updater: Updater, version: String) -> String {
        switch updater.phase {
        case .downloading: "\(Int(updater.fraction * 100))%"
        case .ready, .installing: "Restart to update"
        case .failed: "Retry update"
        default: "Update to \(version)"
        }
    }
}

private struct UpdateActions: View {
    let updater: Updater

    var body: some View {
        let version = updater.release?.version ?? ""
        if let page = updater.release?.page {
            Button("What's new in \(version)") { Link.open(page) }
        }
        Button("Skip \(version)") { updater.skip() }
    }
}

/// The update button's other actions in a menu you can Tab to and open: a context menu opens from the keyboard
/// only on macOS 15 and later.
struct UpdateMenu: View {
    let updater: Updater
    @FocusState private var focused: Bool

    var body: some View {
        Menu { UpdateActions(updater: updater) } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: CDS.Sidebar.symbol, weight: .medium))
                .foregroundStyle(CDS.Text.secondary)
                .frame(width: CDS.RowControl.size, height: CDS.RowControl.size)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More about this update")
        .focused($focused)
        .tip("More about this update", "Release notes, or skip this version", focused: focused)
    }
}

/// The update button's face: its icon (a progress ring while downloading), and its name beside it on hover.
private struct UpdateLabel: View {
    let updater: Updater
    let horizontal: Bool
    let version: String
    @Environment(\.hoverFillHovering) private var hover

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                if updater.phase == .downloading {
                    let fraction = updater.fraction
                    Circle().stroke(CDS.Fill.secondary, lineWidth: 2).padding(4)
                    Circle().trim(from: 0, to: max(0.03, fraction))
                        .stroke(CDS.Fill.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(4)
                        .animation(.linear(duration: 0.2), value: fraction)
                }
                if updater.phase == .installing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: CDS.Sidebar.symbol, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 28, height: 28)
            if horizontal && hover {
                Text(UpdateButton.label(updater, version: version))
                    .font(CDS.sans(CDS.Sidebar.rowFont))
                    .foregroundStyle(CDS.Text.primary)
                    .padding(.trailing, 8)
            }
        }
        .motion(Theme.Motion.spring, value: hover)
    }

    private var symbol: String {
        switch updater.phase {
        case .ready: "arrow.clockwise"
        case .failed: "exclamationmark"
        default: "arrow.down"
        }
    }

    private var tint: Color {
        switch updater.phase {
        case .ready: CDS.Git.added
        case .failed: CDS.Text.danger
        case .downloading: CDS.Text.secondary
        default: CDS.Text.accent
        }
    }
}


struct DrawerRow: View {
    let row: AgentRow
    let store: Store
    @Bindable var ui: UIState
    /// Unused (the switcher numbers are gone); kept so older call sites compile.
    var number: Int = 0
    /// Under/over a horizontal pill: tile, title, then project and status on a second line.
    var twoLines = false
    /// Search: the words to highlight in the title.
    var highlight: String?
    /// Search results mix kept sessions and others: say which aren't in your list.
    var showsKept = false
    /// In the hub, beside its bar tile: padded and highlighted like the inbox's rows (`.rowHighlight`).
    var inHub = false
    /// Inside a larger block that draws the highlight itself (title and details hover as one).
    var plain = false
    /// One-line rows: what it asks, did or is doing, under the title (the hover panel's sessions that need a look).
    var secondLine = false

    typealias M = CDS.Sidebar

    /// Where a row's title starts: Claude's row padding, the hub rail's shift, the 24pt leading slot and the gap (one-line
    /// rows); on two-line rows 10, the slot and 9 (what `SessionBlock` lines its details up with).
    static let titleInset: CGFloat = M.rowPadding + M.railShift + M.leadingSlot + M.rowGap
    static let twoLineTitleInset: CGFloat = 10 + M.leadingSlot + 9

    var body: some View {
        let selected = ui.drawerSelection == row.id
        // Claude's session row (§2.7): the status dot in a 24pt leading slot, 13pt text in secondary (primary when
        // picked), the meta in muted 12 at the end; radius 6, white 7.5% under the pointer.
        let content = HStack(spacing: twoLines ? 9 : M.rowGap) {
            ClaudeDot(kind: ClaudeDot.Kind(row))
                .frame(width: M.leadingSlot, height: twoLines ? 18 : M.leadingSlot)
                .frame(maxHeight: twoLines ? .infinity : nil, alignment: .top)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(CDS.sans(M.rowFont))
                    .foregroundStyle(selected && !plain ? CDS.Text.primary : CDS.Text.secondary)
                    .lineLimit(1)
                    .frame(minHeight: twoLines ? nil : M.rowHeight - 4)
                if twoLines {
                    HStack(spacing: 4) {
                        if showsKept {
                            Text(row.projectName).foregroundStyle(CDS.Text.muted)
                            Text("·").foregroundStyle(CDS.Text.muted)
                            status
                            if !row.entry.kept { Text("· not pinned").foregroundStyle(CDS.Text.muted) }
                        } else {
                            meta
                        }
                    }
                    .font(CDS.sans(CDS.RowControl.detail.0))
                    .lineLimit(1)
                    .padding(.top, 1)
                } else if secondLine {
                    DetailLine(row: row)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 6)

            if selected && !plain {
                AgentActions(row: row, store: store)
            } else if !twoLines {
                // In a hub block the actions are laid over this spot instead: the status steps aside without the
                // row changing size.
                Group { if showsKept { status } else { meta } }
                    .font(CDS.sans(CDS.RowControl.detail.0).monospacedDigit()).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: busy ? 170 : 110, alignment: .trailing)
                    .fixedSize(horizontal: busy, vertical: false)
                    .layoutPriority(busy ? 2 : 0)
                    .opacity(selected && plain ? 0 : 1)
                    .padding(.trailing, 6)
            }
        }
        let shape = RoundedRectangle(cornerRadius: M.radius, style: .continuous)
        content
            .padding(.leading, twoLines ? 10 : M.rowPadding + M.railShift)
            .padding(.trailing, selected && !plain ? CDS.RowControl.inset : M.rowPadding)
            .padding(.vertical, twoLines ? 6 : (secondLine ? 4 : 1))
            .frame(minHeight: twoLines ? 44 : M.rowHeight)
            .frame(maxHeight: twoLines ? 44 : (inHub && !plain ? .infinity : nil))
            .background(shape.fill(selected && !plain ? CDS.Fill.ghostHover : Color.clear))
            .contentShape(shape)
            .motion(Theme.Motion.hover, value: selected)
        .contentShape(Rectangle())
        .onTapGesture { store.openAgent(row.id) }
        .opensOnFirstClick()
        .onHover { if $0 { ui.drawerSelection = row.id } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.session.title)
        .spokenValue(of: row)
        .accessibilityHint(row.spokenHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.openAgent(row.id) }
    }

    /// The status in words keeps a colour only where Claude's dots have one: amber waiting, blue done and unread.
    private var statusColor: Color {
        switch row.group {
        case .needsYou: CDS.Text.warning
        case .done: CDS.Text.accent
        default: CDS.Text.muted
        }
    }

    /// Working, or done with something still running: the status says more than the end of the title.
    private var busy: Bool { row.session.running || !row.tasks.isEmpty }

    /// The title, with what you typed picked out.
    private var title: AttributedString {
        var text = AttributedString(row.session.title)
        let lower = row.session.title.lowercased()
        for word in (highlight ?? "").lowercased().split(separator: " ") {
            var from = lower.startIndex
            while let range = lower.range(of: word, range: from..<lower.endIndex) {
                if let r = Range(NSRange(range, in: lower), in: text) { text[r].foregroundColor = CDS.Fill.warning }
                from = range.upperBound
            }
        }
        return text
    }

    @ViewBuilder private var status: some View {
        if row.session.running {
            WorkingText(row: row)
        } else {
            HStack(spacing: 4) {
                // Its age moves with the same clock as the one VoiceOver is told.
                Ticking(coarse: true) { now in
                    let text = row.statusText(now: now)
                    Text(text).foregroundStyle(statusColor)
                }
                if let tasks = row.tasksText {
                    Text("·").foregroundStyle(CDS.Text.muted)
                    Text(tasks).foregroundStyle(CDS.Text.muted)
                }
            }
        }
    }
}

extension View {
    /// Its taps also take the click that makes the window key. The hub is never key while you hover it from another
    /// app, and a tap gesture otherwise spends that first click on making it key: a row needed two clicks to open.
    /// (Buttons already take it.)
    @ViewBuilder func opensOnFirstClick() -> some View {
        if #available(macOS 15, *) { allowsWindowActivationEvents(true) } else { self }
    }
}

extension DrawerRow {
    /// Its project and how long ago, in grey: the group it's listed under already says its state. While it works, how
    /// long the turn has run; after a turn, what it left running.
    @ViewBuilder var meta: some View {
        HStack(spacing: 4) {
            Text(row.projectName)
            Ticking(coarse: true) { now in
                Text("· " + (row.session.running ? AgentRow.duration(now.timeIntervalSince(row.workingSince ?? now)) : shortAgo(row.session.lastActivity, now: now)))
            }
            if let tasks = row.tasksText { Text("· \(tasks)") }
        }
        .foregroundStyle(CDS.Text.muted)
    }
}

/// Under a session's title: the question it's asking or what it did (its last summary), or what it's doing now.
struct DetailLine: View {
    let row: AgentRow

    var body: some View {
        Group {
            if row.session.running {
                Text(row.activity?.text ?? "Working").foregroundStyle(CDS.Text.muted)
            } else if !row.summaryText.characters.isEmpty {
                Text(row.summaryText).foregroundStyle(CDS.Text.muted)
            } else if !row.tasks.isEmpty {
                RunningLine(tasks: row.tasks)
            } else {
                Text(" ")
            }
        }
        // A second line as Claude's: footnote 12/15, muted.
        .font(CDS.sans(CDS.RowControl.detail.0))
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

/// The drawer's last row: a new scratch session on the row itself, one in a listed project from its tile, and
/// every option by name in the menu when there are more projects than tiles.
struct NewSessionRow: View {
    let store: Store
    var style: Style = .drawer

    enum Style {
        /// The pill's drawer: a small "+" before the label.
        case drawer
        /// The hub, beside its bar cell (the cell is the "+"): the label and the project tiles, padded like a row.
        case detail
        /// The hub's two-line session rows (top and bottom edges): a 24pt "+" tile where theirs sit, 44pt tall.
        case twoLines
    }

    static let maxTiles = 4
    @FocusState private var scratchFocused: Bool
    @FocusState private var menuFocused: Bool

    var body: some View {
        let folders = store.agentFolders
        HStack(spacing: 5) {
            Button { store.startScratchSession() } label: { NewSessionLabel(style: style) }
                .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: CDS.Sidebar.radius, style: .continuous),
                                                  rest: .clear, hover: CDS.Fill.ghostHover, pressed: CDS.Fill.ghostSelected))
                .focused($scratchFocused)
                .tip("New session", "Scratch chat, no folder · or pick a project", focused: scratchFocused)

            let shown = Array(folders.prefix(Self.maxTiles))
            let initials = Self.initials(shown.map { store.folderName($0) })
            ForEach(Array(shown.enumerated()), id: \.element) { i, folder in
                ProjectTile(folder: folder, name: store.folderName(folder), initials: initials[i], color: store.projectColor(folder)) { store.startAgent(in: folder) }
            }
            if folders.count > Self.maxTiles { menu(folders) }
        }
        .padding(.trailing, style == .drawer ? 4 : 8)
        .frame(height: style == .twoLines ? 44 : nil)
        .frame(minHeight: style == .detail ? Theme.Metrics.line : nil)
    }

    private func menu(_ folders: [String]) -> some View {
        Menu {
            Button("Scratch (no folder)") { store.startScratchSession() }
            Divider()
            ForEach(folders, id: \.self) { folder in
                Button(store.folderName(folder)) { store.startAgent(in: folder) }
                    .help(folder)
            }
        } label: {
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(CDS.Text.muted)
        .frame(width: 20, height: 22)
        .focused($menuFocused)
        .tip("New session in…", "Every project, by name", focused: menuFocused)
    }

    /// Two letters per project, told apart from the others shown: the first letters of its first two words
    /// ("lcu-research" → LR), else its first two; on a clash, its first and last.
    static func initials(_ names: [String]) -> [String] {
        func first(_ name: String) -> String {
            let words = name.split { !$0.isLetter && !$0.isNumber }
            if words.count >= 2 { return String([words[0].first!, words[1].first!]) }
            return String(name.filter { $0.isLetter || $0.isNumber }.prefix(2))
        }
        var out = names.map { first($0).uppercased() }
        for i in out.indices where out.firstIndex(of: out[i]) != i {
            let letters = names[i].filter { $0.isLetter || $0.isNumber }
            if let a = letters.first, let b = letters.last { out[i] = String([a, b]).uppercased() }
        }
        return out.map { $0.isEmpty ? "?" : $0 }
    }

    /// The app's new-session link with no folder opens its composer with none picked: a scratch session.
    static func startScratch() {
        guard let url = URL(string: "claude://code/new") else { return }
        Link.open(url)
    }
}

/// The new-session row's button face: Claude's New row (§2.4), its 18pt #2c2c2a circle with a bold + in the 24pt leading
/// slot (muted 25% and primary on hover), then 13pt secondary text, primary on hover.
private struct NewSessionLabel: View {
    let style: NewSessionRow.Style
    @Environment(\.hoverFillHovering) private var hover
    typealias M = CDS.Sidebar

    var body: some View {
        HStack(spacing: style == .twoLines ? 9 : M.rowGap) {
            Image(systemName: "plus")
                .font(.system(size: M.newGlyph, weight: .bold))
                .foregroundStyle(hover ? CDS.Text.primary : CDS.Text.secondary)
                .frame(width: M.newCircle, height: M.newCircle)
                .background(Circle().fill(hover ? CDS.Text.muted.opacity(0.25) : M.newCircleFill))
                .frame(width: M.leadingSlot, height: M.leadingSlot)
            Text("New session").font(CDS.sans(M.rowFont)).foregroundStyle(hover ? CDS.Text.primary : CDS.Text.secondary)
            Spacer(minLength: 4)
        }
        .padding(.leading, style == .twoLines ? 10 : M.rowPadding + M.railShift)
        .frame(minHeight: M.rowHeight)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// A listed project in the new-session row: its initials on a neutral 20pt square (Claude's xs control: radius 5, white
/// 10%, 14% on hover), its colour as a 6pt dot in the corner, its name on hover.
private struct ProjectTile: View {
    let folder: String
    let name: String
    let initials: String
    let color: Color?
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) { ProjectTileFace(initials: initials, color: color) }
            // The face does its own hover look, so the style adds no fill.
            .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: 5, style: .continuous), rest: .clear,
                                              hover: .clear, pressed: .clear))
            .accessibilityLabel("New session in \(name)")
            .focused($focused)
            .tip("New session in \(name)", folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"), focused: focused)
    }
}

private struct ProjectTileFace: View {
    let initials: String
    let color: Color?
    @Environment(\.hoverFillHovering) private var hover

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text(initials)
            .font(CDS.sans(10, .medium))
            .foregroundStyle(hover ? CDS.Text.primary : CDS.Text.secondary)
            .frame(width: 22, height: 22)
            .background(shape.fill(hover ? CDS.Fill.secondaryHover : CDS.Fill.secondary))
            .overlay(alignment: .topTrailing) {
                if let color {
                    Circle().fill(color).frame(width: 5, height: 5)
                        .background(Circle().fill(Color.black).frame(width: 8, height: 8))
                        .offset(x: 2, y: -2)
                }
            }
            .contentShape(shape)
            .motion(Theme.Motion.hover, value: hover)
    }
}

// MARK: - Kept for the hub to adopt (the classic UI's menus and warnings)

/// A session's context menu: open, read state, label, pin/hide, project colour, mute.
struct SessionMenu: View {
    let row: AgentRow
    let store: Store
    /// Opens the label editor (`LabelEditor`) wherever the caller hosts it.
    var editLabel: () -> Void = {}

    var body: some View {
        Button("Open in Claude") { store.openAgent(row.id) }
        Button(row.unread ? "Mark as read" : "Mark as unread") { store.toggleAgentRead(row.id) }
        Button("Change label…") { editLabel() }
        Divider()
        Button(row.entry.kept ? "Unpin" : "Pin") { store.togglePin(row.id) }
        Button("Hide until its next activity") { store.dismissAgent(row.id) }
        if !row.session.folderKey.isEmpty {
            Menu("Colour for \(row.projectName)") {
                ForEach(Theme.projectColorNames.indices, id: \.self) { i in
                    Button(Theme.projectColorNames[i]) { store.setProjectColor(row.session.folderKey, i) }
                }
            }
        }
        // A session found through search can be of a project muted already: muting it again would do nothing.
        if store.isFolderMuted(row.session.folderKey) {
            Button("Unmute \(row.projectName)") { store.setFolderMuted(row.session.folderKey, false) }
        } else {
            Button("Mute \(row.projectName)") { store.setFolderMuted(row.session.folderKey, true) }
        }
    }
}

/// The Claude link's state as a dot and a line ("Synced with Claude", "Claude's sessions not found"…).
struct ClaudeLinkStatus: View {
    let store: Store

    var body: some View {
        let (color, text, detail): (Color, String, String) = switch store.claudeLink {
        case .ok where Claude.isRunning: (Theme.green, "Synced with Claude", "Updates as the Claude app writes its session files")
        case .ok, .off: (Theme.tertiary, "Claude isn't running", "Sessions update again when the app is open")
        case .missing: (Theme.red, "Claude's sessions not found", "Open the Claude desktop app once")
        case .unreadable: (Theme.red, "Can't read Claude's sessions", "The app's session format changed")
        }
        Circle().fill(color).frame(width: 6, height: 6)
        Text(text).tip(text, detail)
    }
}

/// "N API calls left this hour", only when the shared GitHub rate limit is running low.
struct RateLimitWarning: View {
    let store: Store

    var body: some View {
        if let rate = store.rateRemaining, rate < 500 {
            Label("\(rate.formatted()) API calls left this hour", systemImage: "exclamationmark.triangle.fill")
                .monospacedDigit()
                .foregroundStyle(Theme.amber)
                .tip("GitHub rate limit low",
                     "Shared with gh and other tools. Syncing pauses at 0.")
        }
    }
}

extension EnvironmentValues {
    /// Playground only: force a tooltip to show.
    @Entry var previewTip: String? = nil
}
