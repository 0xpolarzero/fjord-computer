import SwiftUI

struct ComputersView: View {
    let store: Store
    let navigator: AppNavigator
    var leadingInset: CGFloat = 0
    private var model: ComputersModel { store.computers }

    var body: some View {
        let rows = model.inventory?.allComputers ?? []
        AppPage(title: "Computers", subtitle: rows.isEmpty ? "" : plural(rows.count, "computer"), leadingInset: leadingInset,
                column: (880, 20)) {
            Menu {
                Button("Linux computer") { Task { await model.createLinuxComputer() } }
                Button("macOS computer") { Task { await model.createMacosComputer() } }
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
                    if let error = model.error {
                        ComputerNotice(text: error, tone: .danger)
                    }
                    if let error = model.actionError { ComputerNotice(text: error, tone: .danger) }
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
            .task { await model.activate() }
            .onDisappear { Task { await model.deactivate() } }
        }
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
                        ComputerOverview(row: row, model: model)
                        if let job = model.activeJob, job.computerId == row.id {
                            ComputerJobCard(job: job, inventory: model.inventory)
                        }
                        ComputerCheckpointSection(row: row, model: model)
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
            .task {
                await model.activate()
                await model.loadCheckpoints(for: computerId)
            }
            .onDisappear { Task { await model.deactivate() } }
        }
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
                        ActionButton("Show display") { Task { await model.showDisplay(row.id) } }
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
        }
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
                        Text(checkpoint.kind == .automatic ? "Automatic" : "Manual")
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

    private var percent: Double? { job.data.progress.map { min(max($0, 0), 1) } }
    private var title: String { job.data.detail ?? job.data.step ?? job.data.state?.capitalized ?? "Working" }
    private var subject: String {
        let id = job.computerId ?? job.data.computerId
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

private struct ComputerPanel<Content: View, Action: View>: View {
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

private extension ComputerCheckpoint {
    var displayName: String {
        let suffix = ", deleted automatically"
        guard kind == .automatic, name.hasSuffix(suffix) else { return name }
        return String(name.dropLast(suffix.count))
    }
}

private extension ComputerPanel where Action == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, action: { EmptyView() }, content: content)
    }
}

private struct ComputerNotice: View {
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
