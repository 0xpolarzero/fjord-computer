import SwiftUI

struct ComputerHostSettings: View {
    let store: Store
    @State private var address = ""
    @State private var pendingRemovalID: String?
    @State private var pendingRemovalName = "this Mac"
    @State private var confirmsRemoval = false
    @State private var checkpointRetentionCount = "3"
    private var model: ComputersModel { store.computers }

    var body: some View {
        VStack(alignment: .leading, spacing: CDS.Settings.sectionGap) {
            computerDefaults.id(SettingsView.computerDefaultsID)
            connections.id(SettingsView.connectedMacsID)
            if let error = model.actionError {
                ComputerNotice(text: error, tone: .danger)
            }
        }
        .task {
            do { try await model.connect() }
            catch { model.actionError = error.localizedDescription }
            await model.loadSettings()
            if let count = model.engineSettings?.settings.automaticCheckpointRetentionCount, count > 0 {
                checkpointRetentionCount = String(count)
            }
            await model.loadConnections()
        }
        .onChange(of: model.engineSettings?.settings.automaticCheckpointRetentionCount) { _, count in
            if let count, count > 0 { checkpointRetentionCount = String(count) }
        }
        .confirmationDialog("Remove access from \(pendingRemovalName)?", isPresented: $confirmsRemoval,
                            titleVisibility: .visible) {
            Button("Remove and revoke key", role: .destructive) {
                guard let pendingRemovalID else { return }
                Task { await model.removeDevice(id: pendingRemovalID) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Fjord revokes this Mac's authorized key on the owner before removing it here. If revocation fails, the connection stays in this list.")
        }
    }

    private var computerDefaults: some View {
        SettingsSection("Computer defaults") {
            SettingsRow("Automatic checkpoints", description: "Keep the latest automatic checkpoints for each computer. Manual checkpoints stay until you delete them.") {
                SettingsSwitch("Automatic checkpoints", isOn: Binding(
                    get: { (model.engineSettings?.settings.automaticCheckpointRetentionCount ?? 3) > 0 },
                    set: { enabled in
                        let count = UInt64(checkpointRetentionCount) ?? 3
                        Task { await model.updateAutomaticCheckpointRetention(enabled ? max(1, count) : 0) }
                    }))
                    .disabled(model.engineSettings == nil || model.engineSettings?.writeProtected == true)
            }
            if (model.engineSettings?.settings.automaticCheckpointRetentionCount ?? 3) > 0 {
                SettingsRow("Retain automatic checkpoints", description: "Choose how many automatic checkpoints each computer keeps.") {
                    HStack(spacing: 7) {
                        TextField("Count", text: $checkpointRetentionCount)
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveCheckpointRetentionCount() }
                        ActionButton("Save") { saveCheckpointRetentionCount() }
                            .disabled(!validCheckpointRetentionCount || model.engineSettings?.writeProtected == true)
                    }
                    .disabled(model.engineSettings == nil || model.engineSettings?.writeProtected == true)
                    .accessibilityLabel("Automatic checkpoint count")
                }
            }
            SettingsDivider()
            SettingsRow("Start computers at launch", description: "Start the selected local computers when Fjord opens.") {
                SettingsSwitch("Start computers at launch", isOn: Binding(
                    get: { model.engineSettings?.settings.startComputersAtLaunch ?? false },
                    set: { enabled in Task { await model.updateStartComputersAtLaunch(enabled) } }))
                    .disabled(model.engineSettings == nil || model.engineSettings?.writeProtected == true)
            }
            if model.engineSettings?.settings.startComputersAtLaunch == true {
                let selected = Set(model.engineSettings?.settings.startupComputerIds ?? [])
                if let computers = model.inventory?.allComputers, !computers.isEmpty {
                    ForEach(computers) { computer in
                        SettingsRow(computer.name, adornment: Self.computerMark(computer.kind)) {
                            Toggle("Start \(computer.name) at launch", isOn: Binding(
                                get: { selected.contains(computer.id) },
                                set: { enabled in
                                    var ids = selected
                                    if enabled { ids.insert(computer.id) } else { ids.remove(computer.id) }
                                    Task { await model.updateStartupComputerIds(ids.sorted()) }
                            }))
                            .labelsHidden()
                            .toggleStyle(CDSSwitchStyle())
                            .disabled(model.engineSettings == nil || model.engineSettings?.writeProtected == true)
                        }
                    }
                    if selected.isEmpty {
                        SettingsNote("With no computers selected, Silo starts its default computer.")
                    }
                } else {
                    SettingsNote("Create a computer before choosing which ones start at launch.")
                }
            }
            if model.engineSettings == nil { SettingsNote("Reading Silo computer settings…") }
            if model.engineSettings?.writeProtected == true {
                SettingsNote("Settings are read-only while another Silo process owns them.")
            }
        }
    }

    private var validCheckpointRetentionCount: Bool {
        guard let count = UInt64(checkpointRetentionCount) else { return false }
        return count > 0 && count != model.engineSettings?.settings.automaticCheckpointRetentionCount
    }

    private func saveCheckpointRetentionCount() {
        guard let count = UInt64(checkpointRetentionCount), count > 0 else {
            model.actionError = "Enter a checkpoint count greater than zero, or turn automatic checkpoints off."
            return
        }
        Task { await model.updateAutomaticCheckpointRetention(count) }
    }

    private var connections: some View {
        SettingsSection("Connected Macs", info: ("Connections", "Connect to a Mac that runs Fjord. Each owner keeps its computers, GitHub credentials and secrets; this Mac holds the SSH connection key."),
                       action: {
            ActionButton("Refresh") { Task { await model.loadConnections() } }
        }) {
            SettingsRow("Allow other Macs to connect", description: "This Mac can act as a computer host for other Fjord devices.") {
                SettingsSwitch("Allow other Macs to connect", isOn: Binding(
                    get: { model.connectionsStatus?.enabled ?? false },
                    set: { enabled in Task { await model.setConnectionsEnabled(enabled) } }))
            }
            if let status = model.connectionsStatus {
                SettingsNote(status.error ?? "Connect using \(status.address).")
                if !status.addresses.isEmpty {
                    Text(status.addresses.map(\.address).joined(separator: "  ·  "))
                        .font(CDS.sans(10).monospaced()).foregroundStyle(CDS.Text.muted)
                        .textSelection(.enabled).padding(.horizontal, 12).padding(.bottom, 8)
                }
            }
            SettingsDivider()
            SettingsRow("Add a Mac", description: "Enter its SSH alias or address, such as user@mac.local.") {
                HStack(spacing: 8) {
                    TextField("user@mac.local", text: $address)
                        .textFieldStyle(.roundedBorder).frame(width: 210)
                    ActionButton("Connect") { addMac() }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if model.actionError?.contains("already saved at") == true {
                        ActionButton("Use this address") {
                            let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task {
                                await model.connectDevice(address: value, replace: true)
                                if model.actionError == nil { address = "" }
                            }
                        }
                    }
                }
            }
            SettingsRow("SSH setup", description: "Run these once for the address above, in order. Confirm the host key, then install Fjord's restricted key.") {
                HStack(spacing: 8) {
                    ActionButton("Authorize SSH") { Task { await model.sshAuthorizationCommand(address: address) } }
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ActionButton("Install Fjord key") { Task { await model.sshKeySetupCommand(address: address) } }
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            SettingsNote("After setup, connect the Mac above. Fjord never copies the private SSH key.")
            if model.connectionDevices.isEmpty {
                SettingsNote("No Macs are connected.")
            } else {
                ForEach(model.connectionDevices, id: \.id) { device in
                    SettingsDivider()
                    let health = model.connectionHealth[device.id]
                    SettingsRow(device.name, description: device.address,
                                below: health?.error.map { AnyView(Text($0).cdsText(CDS.Density.comfortable.footnote, .regular, CDS.Text.warning)) }) {
                        HStack(spacing: 8) {
                            SettingsStatusLine(text: health?.busy == true ? "Busy" : (health?.connected == true ? "Connected" : "Offline"),
                                               color: health?.busy == true ? Theme.amber : (health?.connected == true ? Theme.green : Theme.amber))
                            ActionButton("Remove") {
                                pendingRemovalID = device.id
                                pendingRemovalName = device.name
                                confirmsRemoval = true
                            }
                        }
                    }
                    if let lastSeen = health?.lastSeen {
                        Text("Last seen \(lastSeen)").font(CDS.sans(9)).foregroundStyle(CDS.Text.muted).padding(.leading, 12)
                    }
                }
            }
            if let status = model.connectionsStatus, status.enabled == false {
                SettingsNote("Turn on connections on the owner Mac before adding it here.")
            }
        }
    }

    private func addMac() {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Task {
            await model.connectDevice(address: value)
            if model.actionError == nil { address = "" }
        }
    }

    private static func computerMark(_ kind: ComputerKind) -> AnyView {
        AnyView(Image(systemName: kind == .macos ? "laptopcomputer" : "server.rack")
            .font(.system(size: 11)).foregroundStyle(CDS.Text.secondary))
    }
}
