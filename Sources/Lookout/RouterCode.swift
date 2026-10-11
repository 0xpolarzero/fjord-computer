import SwiftUI

// The Router's window as a sibling of Claude's Code tab: the Router's page (its history, what works on its own, what needs
// you; see RouterPage.swift) over the composer, in the app window's detail area. Built on `RouterModel` and the
// form and plan logic of RouterView.swift; only the presentation is Claude's.

struct RouterCodeView: View {
    let store: Store
    @Bindable var model: RouterModel
    var close: () -> Void = {}
    var checksClaudeCode = true
    /// Inside the app window the detail area sets the size (and the window's top is the window's job); alone it has its own.
    var embedded = false

    static let column: CGFloat = 768

    var body: some View {
        RouterMain(store: store, model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CDS.Surface.s1)
        .frame(minWidth: embedded ? 0 : 760, minHeight: embedded ? 0 : 520)
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
        // Inside the app window, the window's tip space draws the tips: a second one would only measure the page again.
        .tipSpace(!embedded)
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

    var body: some View {
        VStack(spacing: 0) {
            topBar
            RouterSetupNotice(store: store, model: model)
            RouterPageView(store: store, model: model)
                .frame(maxHeight: .infinity)
            RouterComposer(store: store, model: model)
                .frame(maxWidth: RouterCodeView.column)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
    }

    /// §3: a 48pt header holding the 32pt session bar: the glyph and the title (13pt, wght 460, primary).
    private var topBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "bubble.left")
                .font(.system(size: CDS.Sidebar.symbol, weight: .medium))
                .foregroundStyle(CDS.Text.secondary)
                .frame(width: 16, height: 16)
                .padding(.leading, CDS.TitleBar.glyphLeading)
                .accessibilityHidden(true)
            Text("Router")
                .font(CDS.sans(CDS.Density.compact.body.0, .medium))
                .foregroundStyle(CDS.Text.primary)
                .lineLimit(1)
                .padding(.leading, CDS.TitleBar.titleLeading - CDS.TitleBar.glyphLeading - 16)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 24)
        }
        .padding(.trailing, CDS.TitleBar.endInset)
        .frame(height: CDS.TitleBar.bar)
        .frame(height: CDS.TitleBar.header)
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
