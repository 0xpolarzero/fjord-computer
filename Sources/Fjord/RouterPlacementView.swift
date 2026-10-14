import SwiftUI

/// The Runs on control sits in the project suggestion row, beside the place the project is chosen.
struct RunsOnProjectMenu: View {
    let store: Store
    let folder: String
    @State private var computer: ComputerRow?
    @State private var guestPath = ""
    @State private var asksForGuestFolder = false
    @State private var pathError: String?

    private var project: RunsOnProject { store.runsOnProject(for: folder) }
    private var computers: [ComputerRow] { store.computers.inventory?.allComputers ?? [] }

    var body: some View {
        Menu {
            Button("This Mac") { store.setRunsOnPlacement(.thisMac(path: folder), for: folder) }
            if !computers.isEmpty { Divider() }
            ForEach(computers) { row in
                Button {
                    computer = row
                    if case .computer(_, let id, let path) = project.placement, id == row.id {
                        guestPath = path
                    } else {
                        guestPath = ""
                    }
                    asksForGuestFolder = true
                } label: {
                    Label(computerLabel(row), systemImage: row.kind == .linux ? "shippingbox" : "desktopcomputer")
                }
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
        .popover(isPresented: $asksForGuestFolder, arrowEdge: .trailing) {
            guestFolderPrompt
        }
    }

    private var guestFolderPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guest folder").font(.headline)
            if let computer { Text("\(computer.name) · \(computer.kind.title) · \(computer.displayState.title)").font(.caption).foregroundStyle(.secondary) }
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
        case .computer(_, let id, let path):
            let computerName = computers.first(where: { $0.id == id })?.name ?? "Computer"
            return "\(computerName) · \(path)"
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
            store.setRunsOnPlacement(.computer(deviceId: nil, computerId: computer.id, guestPath: path), for: folder)
            asksForGuestFolder = false
            pathError = nil
        } catch {
            pathError = error.localizedDescription
        }
    }
}
