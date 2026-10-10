import AppKit
import SwiftUI

/// A new release, fetched in the background: an icon that says what it is on hover; click to restart into it
/// (or to download it, with a ring for progress, if that didn't happen on its own). Right-click for the release
/// notes or to skip that version; `UpdateMenu` beside it offers the same from the keyboard.
struct UpdateButton: View {
    let updater: Updater
    let horizontal: Bool
    @FocusState private var focused: Bool

    var body: some View {
        let version = updater.release?.version ?? ""
        Button { updater.advance() } label: { UpdateLabel(updater: updater, horizontal: horizontal, version: version) }
        // Claude's ghost chrome button: radius 6, white 7.5% on hover.
        .buttonStyle(HoverFillButtonStyle(shape: RoundedRectangle(cornerRadius: CDS.Sidebar.radius, style: .continuous),
                                          rest: .clear, hover: CDS.Fill.ghostHover, pressed: CDS.Fill.ghostSelected))
        .accessibilityLabel(Self.label(updater, version: version))
        .accessibilityHint(tooltip(version).0)
        .focused($focused)
        .tip(tooltip(version).0, tooltip(version).1, focused: focused)
        .contextMenu { UpdateActions(updater: updater) }
    }

    /// The tooltip: what it is, and what a click does.
    private func tooltip(_ version: String) -> (String, String?) {
        switch updater.phase {
        case .available: ("Lookout \(version) is available", "Click to download it · right-click for more")
        case .downloading: ("Downloading Lookout \(version)… \(Int(updater.fraction * 100))%", nil)
        case .ready: ("Lookout \(version) is ready", "Click to restart into it")
        case .installing: ("Installing Lookout \(version)…", nil)
        case .failed(let message): ("Update failed: \(message)", "Click to try again")
        case .idle: ("", nil)
        }
    }

    fileprivate static func label(_ updater: Updater, version: String) -> String {
        switch updater.phase {
        case .downloading: "\(Int(updater.fraction * 100))%"
        case .ready, .installing: "Restart to update"
        case .failed: "Retry update"
        default: "Update to \(version)"
        }
    }
}

private struct UpdateActions: View {
    let updater: Updater

    var body: some View {
        let version = updater.release?.version ?? ""
        if let page = updater.release?.page {
            Button("What's new in \(version)") { Link.open(page) }
        }
        Button("Skip \(version)") { updater.skip() }
    }
}

/// The update button's other actions in a menu you can Tab to and open: a context menu opens from the keyboard
/// only on macOS 15 and later.
struct UpdateMenu: View {
    let updater: Updater
    @FocusState private var focused: Bool

    var body: some View {
        Menu { UpdateActions(updater: updater) } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: CDS.Sidebar.symbol, weight: .medium))
                .foregroundStyle(CDS.Text.secondary)
                .frame(width: CDS.RowControl.size, height: CDS.RowControl.size)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More about this update")
        .focused($focused)
        .tip("More about this update", "Release notes, or skip this version", focused: focused)
    }
}

/// The update button's face: its icon (a progress ring while downloading), and its name beside it on hover.
private struct UpdateLabel: View {
    let updater: Updater
    let horizontal: Bool
    let version: String
    @Environment(\.hoverFillHovering) private var hover

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                if updater.phase == .downloading {
                    let fraction = updater.fraction
                    Circle().stroke(CDS.Fill.secondary, lineWidth: 2).padding(4)
                    Circle().trim(from: 0, to: max(0.03, fraction))
                        .stroke(CDS.Fill.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(4)
                        .animation(.linear(duration: 0.2), value: fraction)
                }
                if updater.phase == .installing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: CDS.Sidebar.symbol, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 28, height: 28)
            if horizontal && hover {
                Text(UpdateButton.label(updater, version: version))
                    .font(CDS.sans(CDS.Sidebar.rowFont))
                    .foregroundStyle(CDS.Text.primary)
                    .padding(.trailing, 8)
            }
        }
        .motion(Theme.Motion.spring, value: hover)
    }

    private var symbol: String {
        switch updater.phase {
        case .ready: "arrow.clockwise"
        case .failed: "exclamationmark"
        default: "arrow.down"
        }
    }

    private var tint: Color {
        switch updater.phase {
        case .ready: CDS.Git.added
        case .failed: CDS.Text.danger
        case .downloading: CDS.Text.secondary
        default: CDS.Text.accent
        }
    }
}

extension View {
    /// Its taps also take the click that makes the window key. The hub is never key while you hover it from another
    /// app, and a tap gesture otherwise spends that first click on making it key: a row needed two clicks to open.
    /// (Buttons already take it.)
    @ViewBuilder func opensOnFirstClick() -> some View {
        if #available(macOS 15, *) { allowsWindowActivationEvents(true) } else { self }
    }
}
