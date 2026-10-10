import SwiftUI

// The Router's window as a sibling of Claude's Code tab: a sidebar of what needs you (Claude's status dots), and the picked
// card's conversation in the middle, the Router's own when none is picked, over the composer. Built on `RouterModel` and the
// form and plan logic of RouterView.swift; only the presentation is Claude's.

struct RouterCodeView: View {
    let store: Store
    @Bindable var model: RouterModel
    var close: () -> Void = {}
    var checksClaudeCode = true

    static let sidebarWidth: CGFloat = CDS.Sidebar.width
    static let column: CGFloat = 768

    var body: some View {
        HStack(spacing: 0) {
            // §1.6: the sidebar #111 with a 0.5pt white-10% right edge, the page #151515.
            RouterSidebar(store: store, model: model)
                .frame(width: Self.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(CDS.Surface.sidebar)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(CDS.border).frame(width: CDS.Sidebar.edge)
                }
            RouterMain(store: store, model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CDS.Surface.s1)
        }
        .frame(minWidth: 760, minHeight: 520)
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
        .tipSpace()
        // The sidebar runs up under the window's buttons, as in the Code tab.
        .ignoresSafeArea(.container, edges: .top)
        .task { if checksClaudeCode { await model.checkClaudeCode(store) } }
        // Picking a card points the composer at it: what you type next is a reply to that session.
        .onChange(of: model.selection) { _, id in model.replyTo = id }
        .onAppear { if model.replyTo == nil { model.replyTo = model.selection } }
    }
}

// MARK: - Main column

struct RouterMain: View {
    let store: Store
    @Bindable var model: RouterModel

    private var card: RouterCard? { model.selection.flatMap { id in store.router.cards.first { $0.id == id } } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            RouterSetupNotice(store: store, model: model, agent: store.routerAgent)
            ScrollViewReader { proxy in
                ScrollView {
                    // Transcript spec §1: 768 of content between 32 gutters, centred; the top fade strip over it.
                    VStack(alignment: .leading, spacing: 0) {
                        if let card { CardTranscript(store: store, model: model, card: card) } else { RouterTranscript(store: store) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: CDS.Transcript.measure, alignment: .leading)
                    .padding(.horizontal, CDS.Transcript.gutter)
                    .frame(maxWidth: .infinity)
                    .padding(.top, CDS.Transcript.fade)
                    .padding(.bottom, 24)
                }
                .cdsTopFade()
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.router.chat.last?.id) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: model.selection) { proxy.scrollTo("end", anchor: .bottom) }
                // A message asked for (an action's chip): after the conversation is shown, and after the scroll to its end.
                .onChange(of: model.messageRequest, initial: true) { _, request in
                    guard let request, let id = UUID(uuidString: request.id) else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(120))
                        withAnimation(Theme.Motion.hover) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            RouterComposer(store: store, model: model, agent: store.routerAgent)
                .frame(maxWidth: RouterCodeView.column)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
    }

    /// §3: a 48pt header holding the 32pt session bar: the origin glyph, the title (13pt, wght 460, primary), the project
    /// chip, and the 26pt ghost icon buttons at the end, 4 apart, 12 from the edge.
    private var topBar: some View {
        HStack(spacing: 0) {
            // A local session's origin glyph (MEASURED 16pt box; the SF laptop is wide, so a smaller point size).
            Image(systemName: card == nil ? "bubble.left" : "laptopcomputer")
                .font(.system(size: card == nil ? CDS.Sidebar.symbol : 11, weight: .medium))
                .foregroundStyle(CDS.Text.secondary)
                .frame(width: 16, height: 16)
                .padding(.leading, CDS.TitleBar.glyphLeading)
                .accessibilityHidden(true)
            Text(card?.title ?? "Router")
                .font(CDS.sans(CDS.Density.compact.body.0, .medium))
                .foregroundStyle(CDS.Text.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, CDS.TitleBar.titleLeading - CDS.TitleBar.glyphLeading - 16)
                .accessibilityAddTraits(.isHeader)
            if let folder = card?.folder { ProjectChip(name: store.folderName(folder)).padding(.leading, 10) }
            Spacer(minLength: 24)
            if let card {
                HStack(spacing: CDS.TitleBar.buttonGap) {
                    TitleBarButton(symbol: card.isOpen ? "checkmark.circle" : "arrow.uturn.backward.circle",
                                   help: card.isOpen ? "Mark addressed" : "Open again", detail: "Space") {
                        store.setCardAddressed(card.id, card.isOpen)
                    }
                    TitleBarButton(symbol: "arrow.up.right.square", help: "Open in Claude", detail: "Return") {
                        model.open(card.id, store: store)
                    }
                }
            }
        }
        .padding(.trailing, CDS.TitleBar.endInset)
        .frame(height: CDS.TitleBar.bar)
        .frame(height: CDS.TitleBar.header)
    }
}

/// The session bar's icon buttons (§3): CDS ghost icon-only, 26×26, radius 6, a 16pt glyph in secondary (white on hover)
/// over white 7.5% on hover.
private struct TitleBarButton: View {
    let symbol: String
    let help: String
    let detail: String
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: CDS.Sidebar.symbol, weight: .medium))
                .foregroundStyle(hovered ? Color.white : CDS.Text.secondary)
                .frame(width: CDS.TitleBar.button, height: CDS.TitleBar.button)
                .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                    .fill(hovered ? CDS.Fill.ghostHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .focused($focused)
        .accessibilityLabel(help)
        .accessibilityHint(detail)
        .tip(help, detail, focused: focused)
    }
}

/// The project chip beside the title (§3; classes untraced, MEASURED: 17 tall, white 10%, 12pt secondary).
struct ProjectChip: View {
    let name: String
    var body: some View {
        Text(name).font(CDS.sans(CDS.Density.compact.footnote.0)).foregroundStyle(CDS.Text.secondary)
            .lineLimit(1)
            .padding(.horizontal, CDS.TitleBar.chipPadding).frame(height: CDS.TitleBar.chipHeight)
            .background(RoundedRectangle(cornerRadius: CDS.TitleBar.chipRadius, style: .continuous).fill(CDS.TitleBar.chipFill))
    }
}
