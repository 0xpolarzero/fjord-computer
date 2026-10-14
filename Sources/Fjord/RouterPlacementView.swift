import SwiftUI

/// The Runs on control sits in the project suggestion row, beside the place the project is chosen.
struct RunsOnProjectMenu: View {
    let store: Store
    let folder: String
    var opensGuestFolderPromptForShot = false
    @State private var computer: ComputerPlacementOption?
    @State private var guestPath = ""
    @State private var asksForGuestFolder = false
    @State private var pathError: String?

    private var project: RunsOnProject { store.runsOnProject(for: folder) }
    private var placementOptions: [ComputerPlacementOption] { store.computers.placementOptions }

    var body: some View {
        Menu {
            Button("This Mac") { store.setRunsOnPlacement(.thisMac(path: folder), for: folder) }
            if !placementOptions.isEmpty { Divider() }
            ForEach(store.computers.placementOwners) { owner in
                if !owner.options.isEmpty {
                    Section(owner.name) {
                        ForEach(owner.options) { option in
                            Button {
                                computer = option
                                if case .computer(let deviceId, let id, let path) = project.placement,
                                   deviceId == option.deviceId, id == option.computer.id {
                                    guestPath = path
                                } else {
                                    guestPath = ""
                                }
                                asksForGuestFolder = true
                                if option.computer.displayState == .running {
                                    Task { await store.computers.loadAgentTools(GuestReference(deviceId: option.deviceId, computerId: option.computer.id)) }
                                }
                            } label: {
                                Label(computerLabel(option.computer), systemImage: option.computer.kind == .linux ? "shippingbox" : "desktopcomputer")
                            }
                        }
                    }
                }
            }
            if let placementError = store.computers.placementError {
                Divider()
                Button("Refresh computers: \(placementError)") { Task { await store.computers.refreshPlacementInventories() } }
            }
        } label: {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(placementColor)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("Runs on: \(placementTitle)")
        .accessibilityLabel("Runs on: \(placementTitle)")
        .task {
            await store.computers.refreshPlacementInventories()
            guard opensGuestFolderPromptForShot,
                  let option = store.computers.placementOptions.first(where: { $0.deviceId != nil })
                    ?? store.computers.placementOptions.first else { return }
            computer = option
            guestPath = "/workspace/lookout"
            asksForGuestFolder = true
        }
        .popover(isPresented: Binding(get: { asksForGuestFolder && !opensGuestFolderPromptForShot },
                                      set: { if !$0 { asksForGuestFolder = false } }), arrowEdge: .trailing) {
            guestFolderPrompt
        }
        .overlay(alignment: .bottomTrailing) {
            if opensGuestFolderPromptForShot && asksForGuestFolder {
                guestFolderPrompt
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CDS.Surface.s3))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
                    .shadow(color: CDS.PanelShadow.near.color, radius: CDS.PanelShadow.near.radius,
                            y: CDS.PanelShadow.near.y)
                    .offset(x: -40, y: -16)
                    .zIndex(1)
            }
        }
    }

    private var guestFolderPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guest folder").font(.headline)
            if let computer { Text("\(computer.computer.name) · \(computer.ownerName) · \(computer.computer.kind.title) · \(computer.computer.displayState.title)").font(.caption).foregroundStyle(.secondary) }
            TextField("/workspace/project", text: $guestPath).textFieldStyle(.roundedBorder)
                .frame(width: 290)
                .onSubmit { saveGuestFolder() }
            if let computer { agentToolsRow(for: computer) }
            if let pathError { Text(pathError).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { asksForGuestFolder = false }
                Spacer()
                Button("Use folder") { saveGuestFolder() }.keyboardShortcut(.defaultAction)
                    .disabled(computer == nil || guestPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }

    @ViewBuilder private func agentToolsRow(for option: ComputerPlacementOption) -> some View {
        let target = GuestReference(deviceId: option.deviceId, computerId: option.computer.id)
        let model = store.computers
        if let message = model.agentToolsSetupMessage[target.key] {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } else if let status = model.agentTools(for: target), AgentToolsAdvice.needsSetup(status) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Code tools: \(AgentToolsAdvice.headline(status).lowercased()). \(AgentToolsAdvice.detail(status))")
                    .font(.caption).foregroundStyle(.secondary).frame(width: 290, alignment: .leading)
                if option.computer.kind == .linux && option.computer.displayState == .running {
                    Button(AgentToolsAdvice.actionTitle(status)) {
                        Task { await model.setUpAgentTools(target, computerName: option.computer.name) }
                    }
                    .font(.caption)
                    Text("Starting a session sets them up on its own if you skip this.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        if let error = model.agentToolsError[target.key] {
            Text(error).font(.caption).foregroundStyle(.red).frame(width: 290, alignment: .leading)
        }
    }

    private var placementTitle: String {
        switch project.placement {
        case .thisMac: return "This Mac"
        case .computer(let deviceId, let id, let path):
            let option = placementOptions.first { $0.deviceId == deviceId && $0.computer.id == id }
            return "\(option?.computer.name ?? "Computer") · \(option?.ownerName ?? (deviceId ?? "owner")) · \(path)"
        }
    }

    private var placementColor: Color {
        if case .computer = project.placement { return .accentColor }
        return .secondary
    }

    private func computerLabel(_ computer: ComputerRow) -> String {
        let health = computer.detail ?? "Healthy"
        return "\(computer.name) · \(computer.kind.title) · \(computer.displayState.title) · \(health)"
    }

    private func saveGuestFolder() {
        guard let computer else { return }
        do {
            let path = try GuestFolderPath.validate(guestPath)
            store.setRunsOnPlacement(.computer(deviceId: computer.deviceId, computerId: computer.computer.id, guestPath: path), for: folder)
            asksForGuestFolder = false
            pathError = nil
        } catch {
            pathError = error.localizedDescription
        }
    }
}
