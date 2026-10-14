import SwiftUI

/// The handoff stays visible until guest presence and Desktop metadata join it, or the person cancels preparation.
struct RouterPendingDesktopStarts: View {
    let store: Store

    var body: some View {
        Group {
            let pending = store.router.pendingDesktopStarts
            if !pending.isEmpty {
                VStack(spacing: 0) {
                    ForEach(pending) { start in
                    HStack(spacing: 10) {
                        Image(systemName: start.state == .matched ? "checkmark.circle.fill" : "arrow.up.right.square")
                            .foregroundStyle(start.state == .matched ? Theme.accent : Theme.amber)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(start.state == .matched ? "Session found in Claude" : "Ready in Claude")
                                .font(Theme.Typography.bodyStrong)
                            Text("\(store.router.runsOnProjects.first(where: { $0.id == start.projectID })?.name ?? "Project") · \(start.alias) · \(start.folder)")
                                .font(Theme.Typography.meta).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if start.state == .readyInClaude {
                            ActionButton("Open in Claude") {
                                if let url = GuestDesktopStart.reopen(start) { Link.open(url) }
                            }
                            Button("Cancel preparation") { cancel(start) }
                                .buttonStyle(.plain).font(Theme.Typography.meta).foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.vertical, Theme.Space.md)
                    Hairline()
                    }
                }
            }
        }
        .onChange(of: store.claudeSessionsRevision) { GuestRouterRuntime.shared.reconcileDesktopMetadata() }
    }

    private func cancel(_ pending: PendingDesktopStart) {
        var state = store.router
        state.pendingDesktopStarts.removeAll { $0.id == pending.id }
        store.router = state
    }
}
