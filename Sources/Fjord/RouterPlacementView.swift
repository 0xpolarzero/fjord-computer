import SwiftUI

/// The Runs on control sits in the project suggestion row, beside the place the project is chosen.
struct RunsOnProjectMenu: View {
    let store: Store
    let folder: String
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
        .task { await store.computers.refreshPlacementInventories() }
        .popover(isPresented: $asksForGuestFolder, arrowEdge: .trailing) {
            guestFolderPrompt
        }
    }

    private var guestFolderPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guest folder").font(.headline)
            if let computer { Text("\(computer.computer.name) · \(computer.ownerName) · \(computer.computer.kind.title) · \(computer.computer.displayState.title)").font(.caption).foregroundStyle(.secondary) }
            TextField("/workspace/project", text: $guestPath).textFieldStyle(.roundedBorder)
                .frame(width: 290)
                .onSubmit { saveGuestFolder() }
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
