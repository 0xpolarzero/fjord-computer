import SwiftUI

struct ComputersView: View {
    let store: Store
    let navigator: AppNavigator
    var leadingInset: CGFloat = 0
    private var model: ComputersModel { store.computers }

    var body: some View {
        Group {
            if store.computersEngineReady {
                computersPage
            } else {
                EngineEnablePage(store: store)
            }
        }
        .task { await store.inspectComputersEngine() }
    }

    private var computersPage: some View {
        let groups = model.ownerGroups
        let count = groups.reduce(0) { $0 + $1.inventory.allComputers.count }
        return AppPage(title: "Computers", subtitle: count == 0 ? "" : plural(count, "computer"), leadingInset: leadingInset,
                column: (880, 20)) {
            Menu {
                ForEach(groups) { group in
                    if groups.count > 1 { Text(group.name) }
                    Button(groups.count > 1 ? "Linux computer on \(group.name)" : "Linux computer") {
                        model.createSheetKind = .linux
                        model.createDeviceId = group.deviceId
                        model.isCreatePresented = true
                    }
                    Button(groups.count > 1 ? "macOS computer on \(group.name)" : "macOS computer") {
                        model.createSheetKind = .macos
                        model.createDeviceId = group.deviceId
                        model.isCreatePresented = true
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CDS.Text.secondary)
                    .frame(width: 28, height: 28)
                    .background(CDS.Surface.s2, in: Circle())
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .help("Create a computer")
            .accessibilityLabel("Create a computer")
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let launcher = store.engineLauncher { EngineUpdateBanner(store: store, launcher: launcher) }
                    if let error = model.error {
                        ComputerNotice(text: error, tone: .danger)
                    }
                    if let error = model.actionError { ComputerNotice(text: error, tone: .danger) }
                    ComputerOperationQueue(model: model)
                    if let job = model.activeJob {
                        ComputerJobCard(job: job, inventory: model.inventory(for: model.activeJobDeviceId),
                                        ownerName: model.activeJobDeviceId.map { model.ownerName($0) })
                    }
                    if model.isLoading && model.inventory == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 44)
                    } else if count == 0 && model.unreachableOwners.isEmpty {
                        ComputerEmptyState()
                    } else if groups.count == 1 && model.unreachableOwners.isEmpty {
                        ComputerRowList(rows: groups[0].inventory.allComputers, deviceId: nil, navigator: navigator)
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                ComputerOwnerHeader(name: group.name, count: group.inventory.allComputers.count,
                                                    isThisMac: group.deviceId == nil)
                                if group.inventory.allComputers.isEmpty {
                                    SettingsNote("No computers on \(group.name) yet.")
                                } else {
                                    ComputerRowList(rows: group.inventory.allComputers, deviceId: group.deviceId, navigator: navigator)
                                }
                            }
                        }
                        ForEach(model.unreachableOwners) { failure in
                            VStack(alignment: .leading, spacing: 8) {
                                ComputerOwnerHeader(name: failure.device.name, count: nil, isThisMac: false)
                                ComputerNotice(text: "Couldn't load its computers. \(failure.message)", tone: .warning)
                            }
                        }
                    }
                }
                .frame(maxWidth: 880)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
        }
        .sheet(isPresented: Binding(get: { model.isCreatePresented }, set: { model.isCreatePresented = $0 })) {
            if let kind = model.createSheetKind {
                ComputerCreationSheet(store: store, kind: kind)
            }
        }
    }
}

/// A device's name above its computers, on the Computers page once another Mac is connected.
private struct ComputerOwnerHeader: View {
    let name: String
    let count: Int?
    let isThisMac: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isThisMac ? "laptopcomputer" : "network")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(CDS.Text.muted)
            Text(name).font(CDS.sans(12, .semibold)).foregroundStyle(CDS.Text.secondary)
            if let count {
                Text(plural(count, "computer")).font(CDS.sans(11)).foregroundStyle(CDS.Text.muted)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ComputerRowList: View {
    let rows: [ComputerRow]
    let deviceId: String?
    let navigator: AppNavigator

    var body: some View {
        VStack(spacing: 1) {
            ForEach(rows) { row in
                Button { navigator.go(.computerDetail(GuestReference(deviceId: deviceId, computerId: row.id))) } label: {
                    ComputerListRow(row: row)
                }
                .buttonStyle(.plain)
                if row.id != rows.last?.id { Rectangle().fill(CDS.Settings.divider).frame(height: 1) }
            }
        }
        .padding(.horizontal, 14)
        .background(CDS.Surface.s2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
    }
}

private struct EngineEnablePage: View {
    let store: Store
    private var launcher: EngineLauncher? { store.engineLauncher }
    private var state: EngineLaunchState { launcher?.state ?? .missingBundle }

    var body: some View {
        AppPage(title: "Computers", subtitle: "Silo engine", trailing: { EmptyView() }, content: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "server.rack")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(CDS.Text.secondary)
                Text("Computers run in Silo's shared engine")
                    .font(CDS.sans(16, .semibold))
                    .foregroundStyle(CDS.Text.primary)
                Text(state.message)
                    .font(CDS.sans(12))
                    .foregroundStyle(CDS.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch state {
                case .enableRequired:
                    ActionButton("Enable Silo Engine") { Task { await store.enableComputersEngine() } }
                case .awaitingApproval:
                    HStack(spacing: 8) {
                        ActionButton("Open Login Items Settings") { store.openEngineApprovalSettings() }
                        ActionButton("Check approval") { Task { await store.inspectComputersEngine() } }
                    }
                case .failed(_):
                    ActionButton("Retry") { Task { await store.enableComputersEngine() } }
                case .missingBundle:
                    ActionButton("Check again") { Task { await store.inspectComputersEngine() } }
                case .updateBlocked, .connected:
                    EmptyView()
                case .unchecked, .checking, .registering, .waitingForEngine:
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        })
    }
}

struct ComputerDetailView: View {
    let store: Store
    let navigator: AppNavigator
    let target: GuestReference
    var leadingInset: CGFloat = 0
    private var model: ComputersModel { store.computers }
    private var row: ComputerRow? { model.row(target) }
    private var subtitle: String {
        [row?.kind.title, target.deviceId.map { "On \(model.ownerName($0))" }].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        AppPage(title: row?.name ?? "Computer", subtitle: subtitle, leadingInset: leadingInset,
                column: (880, 20)) {
            Button { back() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CDS.Text.secondary)
                    .frame(width: 28, height: 28)
                    .background(CDS.Surface.s2, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to Computers")
            .accessibilityLabel("Back to Computers")
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let row {
                        Picker("Computer section", selection: Binding(get: { model.selectedDetailSection },
                            set: { model.selectedDetailSection = $0 })) {
                            ForEach(ComputerDetailSection.allCases) { section in
                                Text(section.rawValue).tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        ComputerOperationQueue(model: model, target: target)
                        if let job = model.activeJob, model.activeJobDeviceId == target.deviceId,
                           (job.computerId ?? job.data.presentationComputerId) == row.id {
                            ComputerJobCard(job: job, inventory: model.inventory(for: target.deviceId), ownerName: nil)
                        }
                        switch model.selectedDetailSection {
                        case .overview:
                            ComputerOverview(row: row, target: target, model: model)
                            ComputerAgentToolsPanel(row: row, target: target, model: model)
                            ComputerResourcesPanel(row: row, target: target, model: model)
                            ComputerCheckpointSection(row: row, target: target, model: model)
                            ComputerUsePanel(row: row, target: target, model: model)
                        case .files:
                            ComputerFilesPanel(row: row, target: target, model: model)
                        case .network:
                            ComputerNetworkPanel(row: row, target: target, model: model)
                        case .access:
                            ComputerGitHubPanel(row: row, target: target, model: model)
                            ComputerSecretsPanel(row: row, target: target, model: model)
                        case .activity:
                            ComputerActivityPanel(row: row, target: target, model: model)
                        case .storage:
                            ComputerStoragePanel(row: row, target: target, model: model)
                            ComputerExportPanel(row: row, target: target, model: model)
                        }
                    } else if model.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 44)
                    } else {
                        ComputerNotice(text: model.error ?? "This computer is no longer available.", tone: .warning)
                    }
                    if let error = model.actionError { ComputerNotice(text: error, tone: .danger) }
                }
                .frame(maxWidth: 880)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .task(id: "\(target.key)-\(model.selectedDetailSection.rawValue)-\(model.row(target)?.displayState == .running)") {
                switch model.selectedDetailSection {
                case .overview:
                    await model.loadComputerUse(target)
                    if model.row(target)?.displayState == .running {
                        await model.loadAgentTools(target)
                    }
                    await model.loadCheckpointUsage(target)
                case .files:
                    await model.loadFiles(target)
                case .network:
                    await model.loadNetwork(target)
                    await model.loadSSHAccess(target)
                case .access:
                    await model.loadGitHubState(deviceId: target.deviceId)
                    await model.loadSecrets(deviceId: target.deviceId)
                    await model.loadComputerUse(target)
                case .activity:
                    await model.loadSetupActivity(deviceId: target.deviceId)
                    await model.loadLogs(target)
                case .storage:
                    await model.loadStorage(target)
                    await model.loadExportState(deviceId: target.deviceId)
                }
            }
        }
        .sheet(isPresented: Binding(get: { model.pendingViewer != nil }, set: { presented in
            if !presented { Task { await model.closeScreen() } }
        })) {
            if let viewer = model.pendingViewer {
                ComputerViewerSheet(viewer: viewer,
                                    scripts: model.viewerScripts[viewer.connectionId] ?? [],
                                    mockPreview: model.client is MockEngineClient,
                                    onScriptExecuted: { command in
                                        model.acknowledgeViewerScriptCommand(connectionId: command.connectionId,
                                                                            commandId: command.id)
                                    }) {
                    Task { await model.closeScreen() }
                }
            }
        }
        .onDisappear { Task { await model.closeScreen() } }
    }

    private func back() {
        navigator.go(.computers)
    }
}

private struct ComputerListRow: View {
    let row: ComputerRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.kind == .macos ? "laptopcomputer" : "server.rack")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(CDS.Text.secondary)
                .frame(width: 28, height: 28)
                .background(CDS.Surface.s3, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(CDS.sans(13, .medium)).foregroundStyle(CDS.Text.primary).lineLimit(1)
                Text([row.kind.title, row.resources].joined(separator: " · "))
                    .font(CDS.sans(11)).foregroundStyle(CDS.Text.muted).lineLimit(1)
            }
            Spacer(minLength: 10)
            ComputerStateBadge(state: row.displayState, detail: row.detail)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(CDS.Text.muted)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct ComputerStateBadge: View {
    let state: ComputerDisplayState
    var detail: String?

    private var color: Color {
        switch state {
        case .running: Theme.green
        case .failed: CDS.Text.danger
        case .starting, .stopping, .preparing, .copying, .downloading, .installing, .settingUp: CDS.Text.warning
        case .stopped: CDS.Text.muted
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(state.title).font(CDS.sans(11, .medium)).foregroundStyle(CDS.Text.secondary)
            if let detail, detail != state.title {
                Text("·").foregroundStyle(CDS.Text.muted)
                Text(detail).font(CDS.sans(11)).foregroundStyle(CDS.Text.muted).lineLimit(1)
            }
        }
        .fixedSize()
    }
}

private struct ComputerOverview: View {
    let row: ComputerRow
    let target: GuestReference
    let model: ComputersModel

    var body: some View {
        ComputerPanel(title: "Computer") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.name).font(CDS.sans(18, .semibold)).foregroundStyle(CDS.Text.primary)
                        Text(row.kind.title + " · " + row.resources).font(CDS.sans(12)).foregroundStyle(CDS.Text.muted)
                    }
                    Spacer()
                    ComputerStateBadge(state: row.displayState, detail: row.detail)
                }
                if let version = osVersion {
                    SettingsNote(version).padding(.top, 8)
                }
                if target.deviceId != nil {
                    SettingsNote("On \(model.ownerName(target.deviceId)). Every action runs on that Mac.").padding(.top, 8)
                }
                SettingsDivider().padding(.vertical, 14)
                HStack(spacing: 8) {
                    if row.canStart {
                        ActionButton("Start") { Task { await model.start(target) } }
                    }
                    if row.canStop {
                        ActionButton("Stop") { Task { await model.stop(target) } }
                    }
                    if row.canForceStop {
                        ActionButton("Force stop") { Task { await model.forceStop(target) } }
                    }
                    if row.canShowDisplay {
                        ActionButton("Open screen") { Task { await model.openScreen(for: target) } }
                            .disabled(displayUnavailable != nil)
                    }
                    if row.canDelete {
                        ActionButton("Delete") { Task { await model.delete(target) } }
                    }
                }
                if let displayUnavailable {
                    SettingsNote(displayUnavailable).padding(.top, 8)
                }
            }
        }
    }

    /// A macOS computer's window opens on its owner; a Linux computer's screen is opened here through the viewer.
    private var displayUnavailable: String? {
        row.kind == .macos ? ComputerRemoteLimit.display.unavailableReason(for: target) : nil
    }

    private var osVersion: String? {
        guard case .macos(let computer) = row else { return nil }
        return computer.osVersion
    }
}

private struct ComputerCheckpointSection: View {
    let row: ComputerRow
    let target: GuestReference
    let model: ComputersModel

    var body: some View {
        ComputerPanel(title: "Checkpoints", action: {
            ActionButton("Create checkpoint") { Task { await model.createCheckpoint(for: target) } }
                .disabled(row.displayState != .running && row.displayState != .stopped)
        }) {
            if let usage = model.checkpointUsage[target.key] {
                SettingsNote("\(usage.checkpoints.count) checkpoints · \(usage.totalBytes.map(byteCount) ?? "size unavailable")")
            }
            if row.checkpoints.isEmpty {
                SettingsNote("No checkpoints yet")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(row.checkpoints.enumerated()), id: \.element.id) { index, checkpoint in
                        CheckpointRow(checkpoint: checkpoint, computer: row, target: target, model: model)
                        if index < row.checkpoints.count - 1 { SettingsDivider() }
                    }
                }
            }
            if hasPendingRestore {
                SettingsDivider().padding(.vertical, 6)
                ComputerNotice(text: "A checkpoint restore needs attention. Abandoning it clears the pending restore; it does not restore files.", tone: .warning)
                ActionButton("Abandon pending restore") { Task { await model.abandonRestore(target) } }
            }
        }
    }

    private var hasPendingRestore: Bool {
        switch row {
        case .linux(let value): value.pendingCheckpointRestore != nil || value.unfinishedRestore != nil
        case .macos(let value): value.pendingRestore != nil
        }
    }

    private func byteCount(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
}

private struct CheckpointRow: View {
    let checkpoint: ComputerCheckpoint
    let computer: ComputerRow
    let target: GuestReference
    let model: ComputersModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: checkpoint.kind == .automatic ? "clock.arrow.circlepath" : "externaldrive")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(CDS.Text.secondary).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(checkpoint.displayName).font(CDS.sans(12, .medium)).foregroundStyle(CDS.Text.primary)
                    HStack(spacing: 6) {
                        Text(checkpoint.kindLabel)
                        Text("·")
                        Text(checkpoint.scope.rawValue.capitalized)
                        if checkpoint.kind == .automatic {
                            Text("·")
                            Text("deleted automatically")
                        }
                        Text("·")
                        Text(checkpoint.createdAt, isoDateStyle: true)
                    }
                    .font(CDS.sans(10)).foregroundStyle(CDS.Text.muted)
                }
                Spacer(minLength: 8)
            }
            HStack(spacing: 8) {
                ActionButton("Restore") { Task { await model.restoreCheckpoint(checkpoint.id, on: target) } }
                ActionButton("Fork") { Task { await model.forkCheckpoint(checkpoint.id, on: target, computerName: computer.name) } }
                if checkpoint.kind == .manual {
                    ActionButton("Delete") { Task { await model.deleteCheckpoint(checkpoint.id, on: target) } }
                }
            }
            .padding(.leading, 22)
        }
        .padding(.vertical, 13)
    }
}

private struct ComputerJobCard: View {
    let job: OperationJobProgress
    let inventory: ComputerInventory?
    /// The device the job runs on, when it is not This Mac.
    let ownerName: String?

    private var percent: Double? { job.data.presentationProgress.map { min(max($0, 0), 1) } }
    private var title: String { job.data.presentationTitle ?? "Working" }
    private var subject: String {
        let id = job.computerId ?? job.data.presentationComputerId
        let subject = id.flatMap { inventory?.computer($0) }.map { "\($0.name) · \($0.kind.title)" } ?? job.jobId
        return ownerName.map { "\(subject) · \($0)" } ?? subject
    }

    var body: some View {
        ComputerPanel(title: "In progress") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(CDS.sans(12, .medium)).foregroundStyle(CDS.Text.primary)
                    Spacer()
                    if let percent { Text("\(Int(percent * 100))%")
                        .font(CDS.sans(11).monospacedDigit()).foregroundStyle(CDS.Text.muted) }
                }
                ProgressView(value: percent).tint(CDS.Text.accent)
                Text(subject).font(CDS.sans(10)).foregroundStyle(CDS.Text.muted)
            }
        }
    }
}

private struct ComputerOperationQueue: View {
    let model: ComputersModel
    /// The computer whose queue to show; nil shows every owner's.
    var target: GuestReference? = nil

    private struct Item: Identifiable {
        var deviceId: String?
        var entry: OperationQueueEntry
        var id: String { "\(GuestReference.ownerKey(deviceId))/\(entry.id)" }
    }

    private var owners: [String?] {
        if let target { return [target.deviceId] }
        return [nil] + model.remoteOwnerInventories.compactMap(\.deviceId)
    }

    private var running: [Item] { items { $0.running } }
    private var waiting: [Item] { items { $0.waiting } }

    private func items(_ pick: (OperationsList) -> [OperationQueueEntry]) -> [Item] {
        owners.flatMap { owner in
            let queue = model.operationQueues[GuestReference.ownerKey(owner)] ?? .empty
            return pick(queue)
                .filter { entry in target.map { entry.computerId == nil || entry.computerId == $0.computerId } ?? true }
                .map { Item(deviceId: owner, entry: $0) }
        }
    }

    var body: some View {
        if !running.isEmpty || !waiting.isEmpty {
            ComputerPanel(title: "Operation queue") {
                VStack(spacing: 0) {
                    ForEach(running) { item in
                        ComputerOperationQueueRow(entry: item.entry, deviceId: item.deviceId, status: "Running", model: model,
                                                  showsOwner: target == nil && owners.count > 1)
                        if item.id != running.last?.id || !waiting.isEmpty { SettingsDivider() }
                    }
                    ForEach(waiting) { item in
                        ComputerOperationQueueRow(entry: item.entry, deviceId: item.deviceId, status: "Waiting…", model: model,
                                                  showsOwner: target == nil && owners.count > 1)
                        if item.id != waiting.last?.id { SettingsDivider() }
                    }
                }
            }
        }
    }
}

private struct ComputerOperationQueueRow: View {
    let entry: OperationQueueEntry
    let deviceId: String?
    let status: String
    let model: ComputersModel
    var showsOwner = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.label).font(CDS.sans(12, .medium)).foregroundStyle(CDS.Text.primary)
                Text([entry.computerName ?? entry.computerId ?? entry.kind, showsOwner ? model.ownerName(deviceId) : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(CDS.sans(10)).foregroundStyle(CDS.Text.muted)
            }
            Spacer(minLength: 8)
            Text(status).font(CDS.sans(11)).foregroundStyle(status == "Waiting…" ? CDS.Text.warning : CDS.Text.muted)
            if entry.cancellable, let jobId = entry.jobId {
                Button("Cancel") { Task { await model.cancelJob(jobId, deviceId: deviceId) } }
                    .buttonStyle(.plain)
                    .font(CDS.sans(11, .medium))
                    .foregroundStyle(CDS.Text.accent)
            }
        }
        .padding(.vertical, 10)
    }
}

struct ComputerPanel<Content: View, Action: View>: View {
    let title: String
    @ViewBuilder var action: () -> Action
    @ViewBuilder var content: () -> Content

    init(title: String, @ViewBuilder action: @escaping () -> Action, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.action = action
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(CDS.sans(12, .semibold)).foregroundStyle(CDS.Text.secondary)
                Spacer()
                action()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CDS.Surface.s2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
    }
}

extension ComputerCheckpoint {
    /// Where the checkpoint came from, read from the engine's `kind` field.
    var kindLabel: String { kind == .automatic ? "Automatic" : "Manual" }

    var displayName: String {
        let suffix = ", deleted automatically"
        guard kind == .automatic, name.hasSuffix(suffix) else { return name }
        return String(name.dropLast(suffix.count))
    }
}

extension ComputerPanel where Action == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, action: { EmptyView() }, content: content)
    }
}

/// The engine update: asked for, running (with its step), blocked before the swap, or done.
private struct EngineUpdateBanner: View {
    let store: Store
    let launcher: EngineLauncher

    var body: some View {
        if let message = launcher.update.message {
            HStack(spacing: 10) {
                if case .running = launcher.update { ProgressView().controlSize(.small) }
                Text(message).font(CDS.sans(12)).foregroundStyle(tone)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let action {
                    ActionButton(action) { Task { await store.updateComputersEngine() } }
                }
            }
            .padding(14)
            .background(CDS.Surface.s2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var tone: Color {
        switch launcher.update {
        case .blocked: CDS.Text.warning
        case .failed: CDS.Text.danger
        default: CDS.Text.secondary
        }
    }

    private var action: String? {
        switch launcher.update {
        case .available: launcher.updateStartsAutomatically ? nil : "Update engine"
        case .blocked: "Try again"
        default: nil
        }
    }
}

struct ComputerNotice: View {
    enum Tone { case warning, danger }
    let text: String
    let tone: Tone
    var body: some View {
        Text(text).font(CDS.sans(12)).foregroundStyle(tone == .danger ? CDS.Text.danger : CDS.Text.warning)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(CDS.Surface.s2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct ComputerEmptyState: View {
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "desktopcomputer").font(.system(size: 22)).foregroundStyle(CDS.Text.muted)
            Text("No computers yet").font(CDS.sans(13, .medium)).foregroundStyle(CDS.Text.secondary)
            Text("Create a Linux or macOS computer to get started.").font(CDS.sans(11)).foregroundStyle(CDS.Text.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }
}

struct ComputersQuitDialog: View {
    let prompt: ComputerQuitPrompt
    let working: Bool
    let error: String?
    let choose: (ComputerQuitChoice) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text(prompt.message).font(CDS.sans(14, .medium)).foregroundStyle(CDS.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !prompt.runningComputers.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(prompt.runningComputers) { computer in
                            HStack(spacing: 8) {
                                Circle().fill(Theme.green).frame(width: 6, height: 6)
                                Text(computer.name).font(CDS.sans(12, .medium)).foregroundStyle(CDS.Text.primary)
                                Text(computer.kind.title).font(CDS.sans(11)).foregroundStyle(CDS.Text.muted)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CDS.Surface.s3, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let error { Text(error).font(CDS.sans(12)).foregroundStyle(CDS.Text.danger).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { choose(.cancel) }.buttonStyle(SettingsButtonStyle(size: .sm)).disabled(working)
                    Button("Keep running") { choose(.keepRunning) }.buttonStyle(SettingsButtonStyle(size: .sm)).disabled(working)
                    Button(working ? "Stopping…" : "Stop and quit") { choose(.stopAndQuit) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(working || prompt.inspectionError != nil)
                }
            }
            .padding(22)
            .frame(width: 500)
            .background(CDS.Surface.s1, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 28, y: 12)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
    }
}

private extension Text {
    init(_ isoDate: String, isoDateStyle: Bool) {
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: isoDate) ?? ISO8601DateFormatter().date(from: isoDate.replacingOccurrences(of: ".000Z", with: "Z"))
        self.init(date.map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) } ?? isoDate)
    }
}
