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
        let rows = model.inventory?.allComputers ?? []
        return AppPage(title: "Computers", subtitle: rows.isEmpty ? "" : plural(rows.count, "computer"), leadingInset: leadingInset,
                column: (880, 20)) {
            Menu {
                Button("Linux computer") {
                    model.createSheetKind = .linux
                    model.isCreatePresented = true
                }
                Button("macOS computer") {
                    model.createSheetKind = .macos
                    model.isCreatePresented = true
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
                    if let job = model.activeJob { ComputerJobCard(job: job, inventory: model.inventory) }
                    if model.isLoading && model.inventory == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 44)
                    } else if rows.isEmpty {
                        ComputerEmptyState()
                    } else {
                        VStack(spacing: 1) {
                            ForEach(rows) { row in
                                Button { navigator.go(.computerDetail(row.id)) } label: {
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
    let computerId: String
    var leadingInset: CGFloat = 0
    private var model: ComputersModel { store.computers }
    private var row: ComputerRow? { model.inventory?.computer(computerId) }

    var body: some View {
        AppPage(title: row?.name ?? "Computer", subtitle: row?.kind.title ?? "", leadingInset: leadingInset,
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
                        ComputerOperationQueue(model: model, computerId: row.id)
                        if let job = model.activeJob, job.computerId == row.id {
                            ComputerJobCard(job: job, inventory: model.inventory)
                        }
                        switch model.selectedDetailSection {
                        case .overview:
                            ComputerOverview(row: row, model: model)
                            ComputerResourcesPanel(row: row, model: model)
                            ComputerCheckpointSection(row: row, model: model)
                            ComputerUsePanel(row: row, model: model)
                        case .files:
                            ComputerFilesPanel(row: row, model: model)
                        case .network:
                            ComputerNetworkPanel(row: row, model: model)
                        case .access:
                            ComputerGitHubPanel(row: row, model: model)
                            ComputerSecretsPanel(row: row, model: model)
                        case .activity:
                            ComputerActivityPanel(row: row, model: model)
                        case .storage:
                            ComputerStoragePanel(row: row, model: model)
                            ComputerExportPanel(row: row, model: model)
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
            .task(id: "\(computerId)-\(model.selectedDetailSection.rawValue)") {
                switch model.selectedDetailSection {
                case .overview:
                    await model.loadComputerUse(computerId: computerId)
                    await model.loadCheckpointUsage(computerId: computerId)
                case .files:
                    await model.loadFiles(computerId: computerId)
                case .network:
                    await model.loadNetwork(computerId: computerId)
                    await model.loadSSHAccess(computerId: computerId)
                case .access:
                    await model.loadGitHubState()
                    await model.loadSecrets()
                    await model.loadComputerUse(computerId: computerId)
                case .activity:
                    await model.loadSetupActivity()
                    await model.loadLogs(computerId: computerId)
                case .storage:
                    await model.loadStorage(computerId: computerId)
                    await model.loadExportState()
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
                SettingsDivider().padding(.vertical, 14)
                HStack(spacing: 8) {
                    if row.canStart {
                        ActionButton("Start") { Task { await model.start(row.id) } }
                    }
                    if row.canStop {
                        ActionButton("Stop") { Task { await model.stop(row.id) } }
                    }
                    if row.canForceStop {
                        ActionButton("Force stop") { Task { await model.forceStop(row.id) } }
                    }
                    if row.canShowDisplay {
                        ActionButton("Open screen") { Task { await model.openScreen(for: row.id) } }
                    }
                    if row.canDelete {
                        ActionButton("Delete") { Task { await model.delete(row.id) } }
                    }
                }
            }
        }
    }

    private var osVersion: String? {
        guard case .macos(let computer) = row else { return nil }
        return computer.osVersion
    }
}

private struct ComputerCheckpointSection: View {
    let row: ComputerRow
    let model: ComputersModel

    var body: some View {
        ComputerPanel(title: "Checkpoints", action: {
            ActionButton("Create checkpoint") { Task { await model.createCheckpoint(for: row.id) } }
                .disabled(row.displayState != .running && row.displayState != .stopped)
        }) {
            if let usage = model.checkpointUsage[row.id] {
                SettingsNote("\(usage.checkpoints.count) checkpoints · \(usage.totalBytes.map(byteCount) ?? "size unavailable")")
            }
            if row.checkpoints.isEmpty {
                SettingsNote("No checkpoints yet")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(row.checkpoints.enumerated()), id: \.element.id) { index, checkpoint in
                        CheckpointRow(checkpoint: checkpoint, computer: row, model: model)
                        if index < row.checkpoints.count - 1 { SettingsDivider() }
                    }
                }
            }
            if hasPendingRestore {
                SettingsDivider().padding(.vertical, 6)
                ComputerNotice(text: "A checkpoint restore needs attention. Abandoning it clears the pending restore; it does not restore files.", tone: .warning)
                ActionButton("Abandon pending restore") { Task { await model.abandonRestore(computerId: row.id) } }
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
                ActionButton("Restore") { Task { await model.restoreCheckpoint(checkpoint.id, computerId: computer.id) } }
                ActionButton("Fork") { Task { await model.forkCheckpoint(checkpoint.id, computerId: computer.id, computerName: computer.name) } }
                if checkpoint.kind == .manual {
                    ActionButton("Delete") { Task { await model.deleteCheckpoint(checkpoint.id, computerId: computer.id) } }
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

    private var percent: Double? { job.data.presentationProgress.map { min(max($0, 0), 1) } }
    private var title: String { job.data.presentationTitle ?? "Working" }
    private var subject: String {
        let id = job.computerId ?? job.data.presentationComputerId
        return id.flatMap { inventory?.computer($0) }.map { "\($0.name) · \($0.kind.title)" } ?? job.jobId
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
    var computerId: String? = nil

    private var running: [OperationQueueEntry] {
        entries(model.operationQueue.running)
    }

    private var waiting: [OperationQueueEntry] {
        entries(model.operationQueue.waiting)
    }

    var body: some View {
        if !running.isEmpty || !waiting.isEmpty {
            ComputerPanel(title: "Operation queue") {
                VStack(spacing: 0) {
                    ForEach(running) { entry in
                        ComputerOperationQueueRow(entry: entry, status: "Running", model: model)
                        if entry.id != running.last?.id || !waiting.isEmpty { SettingsDivider() }
                    }
                    ForEach(waiting) { entry in
                        ComputerOperationQueueRow(entry: entry, status: "Waiting…", model: model)
                        if entry.id != waiting.last?.id { SettingsDivider() }
                    }
                }
            }
        }
    }

    private func entries(_ entries: [OperationQueueEntry]) -> [OperationQueueEntry] {
        guard let computerId else { return entries }
        return entries.filter { $0.computerId == nil || $0.computerId == computerId }
    }
}

private struct ComputerOperationQueueRow: View {
    let entry: OperationQueueEntry
    let status: String
    let model: ComputersModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.label).font(CDS.sans(12, .medium)).foregroundStyle(CDS.Text.primary)
                Text(entry.computerName ?? entry.computerId ?? entry.kind)
                    .font(CDS.sans(10)).foregroundStyle(CDS.Text.muted)
            }
            Spacer(minLength: 8)
            Text(status).font(CDS.sans(11)).foregroundStyle(status == "Waiting…" ? CDS.Text.warning : CDS.Text.muted)
            if entry.cancellable, let jobId = entry.jobId {
                Button("Cancel") { Task { await model.cancelJob(jobId) } }
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
