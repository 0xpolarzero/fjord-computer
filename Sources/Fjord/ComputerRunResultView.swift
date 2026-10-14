import AVFoundation
import SwiftUI

/// The durable result shown from a Triage action chip. The screen does not infer success from a model's text.
struct ComputerRunResultView: View {
    let store: Store
    let runID: UUID
    var leadingInset: CGFloat = 0

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var poster: NSImage?

    private var record: ComputerRunRecord? { store.actionLedger.computerRuns[runID] }

    var body: some View {
        AppPage(title: "Triage run", subtitle: record?.computerName ?? "Run result", leadingInset: leadingInset,
                column: AppPage<EmptyView, EmptyView>.inboxColumn, trailing: { EmptyView() }) {
            if let record {
                resultCard(record)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                    .frame(maxWidth: InboxListView.column)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ContentUnavailableView("Run record unavailable", systemImage: "desktopcomputer",
                                       description: Text("Fjord could not find this Triage run in actions.json."))
            }
        }
        .task(id: runID) {
            await store.acknowledgeComputerRun(runID)
            Task { await store.resumeComputerRun(runID) }
        }
        .onChange(of: record?.phase) { _, phase in
            guard phase?.isTerminal == true else { return }
            Task { await store.acknowledgeComputerRun(runID) }
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
    }

    @ViewBuilder
    private func resultCard(_ run: ComputerRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: run.phase == .result ? "checkmark.circle.fill" : "desktopcomputer")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(run.phase == .result ? CDS.Git.added : CDS.Text.accent)
                    .frame(width: 34, height: 34)
                    .background(CDS.Surface.s2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.taskTitle.isEmpty ? "Computer run" : run.taskTitle)
                        .cdsText(CDS.Density.comfortable.heading, .semibold, CDS.Text.primary)
                        .textSelection(.enabled)
                    Text("\(run.computerName) · \(run.repo) · \(run.phase.title)")
                        .cdsText(CDS.Density.compact.footnote, .regular, CDS.Text.secondary)
                }
                Spacer(minLength: 0)
                if let exitCode = run.exitCode {
                    Text("Exit \(exitCode)")
                        .cdsText(CDS.Density.compact.caption, .medium, exitCode == 0 ? CDS.Text.secondary : CDS.Text.danger)
                }
            }

            Text(run.summary ?? run.detail)
                .cdsText(CDS.Density.compact.body, .regular, CDS.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                if let branchURL = branchURL(run) {
                    SwiftUI.Link(destination: branchURL) {
                        Label(run.branch, systemImage: "arrow.branch")
                            .cdsText(CDS.Density.compact.footnote, .medium, CDS.Text.accent)
                            .lineLimit(1)
                    }
                } else {
                    Label(run.branch, systemImage: "arrow.branch")
                        .cdsText(CDS.Density.compact.footnote, .medium, CDS.Text.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                if let pullRequestURL = run.pullRequestURL {
                    SwiftUI.Link(destination: pullRequestURL) {
                        Label("Open pull request", systemImage: "arrow.up.right.square")
                            .cdsText(CDS.Density.compact.footnote, .medium, CDS.Text.accent)
                    }
                }
            }

            if run.summaryUnverified {
                Label("Claude's summary is unverified by Fjord.", systemImage: "info.circle")
                    .cdsText(CDS.Density.compact.caption, .regular, CDS.Text.muted)
            }

            if run.proofRequested { proofPlayer(run) }

            HStack(spacing: 8) {
                Button("Open in Claude") { Task { await store.openComputerRunInClaude(run.id) } }
                    .buttonStyle(SettingsButtonStyle(size: .sm))
                Button(run.rolledBackAt == nil ? "Roll Back" : "Restored") {
                    Task { await store.rollbackComputerRun(run.id) }
                }
                .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .sm))
                .disabled(run.checkpointID == nil || run.rolledBackAt != nil
                          || run.phase.isEngineOwnedActive || run.phase == .unconfirmed)
                if run.phase.isEngineOwnedActive || (run.phase == .unconfirmed && run.execJobID != nil) {
                    Button("Cancel run") { Task { await store.cancelComputerRun(run.id) } }
                        .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .sm))
                }
                Spacer(minLength: 0)
            }

            if let rollbackError = run.rollbackError, !rollbackError.isEmpty {
                Text(rollbackError).cdsText(CDS.Density.compact.footnote, .regular, CDS.Text.danger)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CDS.Surface.s2))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))
    }

    @ViewBuilder
    private func proofPlayer(_ run: ComputerRunRecord) -> some View {
        if let path = run.localVideoPath, FileManager.default.fileExists(atPath: path) {
            GeometryReader { proxy in
                ZStack {
                    Color.black
                    RunVideoSurface(player: player)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    if !isPlaying, let poster {
                        Image(nsImage: poster)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: path) {
                player?.pause()
                let url = URL(fileURLWithPath: path)
                player = AVPlayer(url: url)
                poster = Self.videoPoster(at: url)
                isPlaying = false
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CDS.border, lineWidth: 1))

            HStack(spacing: 10) {
                Button {
                    if isPlaying {
                        player?.pause()
                        isPlaying = false
                    } else {
                        player?.play()
                        isPlaying = true
                    }
                } label: {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(SettingsButtonStyle(variant: .ghost, size: .sm))
                Text(run.videoDurationSeconds.map { "Proof video · \(Int($0.rounded())) seconds" } ?? "Proof video")
                    .cdsText(CDS.Density.compact.caption, .medium, CDS.Text.secondary)
                Spacer(minLength: 0)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.82))
                VStack(spacing: 8) {
                    Image(systemName: run.proofState == .complete ? "play.circle.fill" : "video.badge.waveform")
                        .font(.system(size: 34, weight: .regular))
                    Text(proofLabel(run))
                        .cdsText(CDS.Density.compact.footnote, .medium, .white)
                    if let duration = run.videoDurationSeconds {
                        Text("\(Int(duration.rounded())) seconds")
                            .cdsText(CDS.Density.compact.caption, .regular, .white.opacity(0.75))
                    }
                }
                .foregroundStyle(.white.opacity(0.88))
            }
            .frame(height: 190)
            .accessibilityLabel("Proof video: \(proofLabel(run))")
        }
    }

    private func proofLabel(_ run: ComputerRunRecord) -> String {
        switch run.proofState {
        case .notRequested: "Proof recording off"
        case .notStarted: "Proof recording did not start"
        case .starting where run.phase == .unconfirmed: "Recorder status is unconfirmed"
        case .starting: "Waiting for the guest recorder"
        case .complete: "Proof video retrieved from the guest"
        case .partial: "Partial proof video retrieved from the guest"
        case .failed: "Guest proof recording failed"
        }
    }

    private func branchURL(_ run: ComputerRunRecord) -> URL? {
        guard InboxActions.trustedRepo(run.repo) == run.repo,
              run.branch.range(of: #"^fjord/triage/[a-z0-9-]+-[a-f0-9]{8}$"#, options: .regularExpression) != nil else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(run.repo)/tree/\(run.branch)"
        return components.url
    }

    private static func videoPoster(at url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let frame = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return NSImage(cgImage: frame, size: .zero)
    }
}

private struct RunVideoSurface: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> RunVideoHostView {
        let view = RunVideoHostView()
        view.wantsLayer = true
        view.playerLayer?.player = player
        return view
    }

    func updateNSView(_ view: RunVideoHostView, context: Context) {
        view.playerLayer?.player = player
    }
}

private final class RunVideoHostView: NSView {
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }

    var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

    override func layout() {
        super.layout()
        playerLayer?.videoGravity = .resizeAspect
    }
}
