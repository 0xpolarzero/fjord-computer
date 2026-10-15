import Observation
import SwiftUI

/// Silo's engine keeps its sign-in, secrets and per-computer proxy certificates in the macOS Keychain. A self-signed engine
/// build is a new program to the Keychain after every update, so it is refused those items until the user allows it once.
/// The engine never asks by itself: `engine.credentials.repair` is called only from the button below.
@MainActor
@Observable
final class KeychainAccessModel {
    private(set) var status: SiloWireCredentialsStatus?
    private(set) var isRepairing = false
    /// What the last repair left blocked, in words; nil when nothing is.
    private(set) var stillBlocked: String?
    /// The repair itself failed (not a refusal by the user).
    private(set) var failure: String?

    var deniedCount: Int { status?.deniedCount ?? 0 }

    func refresh(using client: any EngineClient) async {
        // An older engine has no such method; the page then relies on the errors it already shows.
        status = try? await client.invoke(SiloGeneratedMethods.engineCredentialsStatus(SiloWireEmptyParams()))
    }

    /// Returns whether every item is usable again.
    @discardableResult
    func repair(using client: any EngineClient) async -> Bool {
        guard !isRepairing else { return false }
        isRepairing = true
        failure = nil
        stillBlocked = nil
        defer { isRepairing = false }
        do {
            let result = try await client.invoke(SiloGeneratedMethods.engineCredentialsRepair(SiloWireEmptyParams()))
            status = result.status
            let blocked = result.items.filter { $0.outcome == .stillDenied || $0.outcome == .failed }
            if !blocked.isEmpty {
                stillBlocked = Self.blockedMessage(blocked)
            }
            return result.status.deniedCount == 0
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    static func blockedMessage(_ items: [SiloWireCredentialRepairItem]) -> String {
        var labels: [String] = []
        for item in items where !labels.contains(item.label) { labels.append(item.label) }
        return "Still blocked: \(labels.joined(separator: ", ")). Choose Always Allow in the macOS dialog, then try again."
    }
}

extension EngineErrorText {
    /// The engine's refusal by the Keychain, in the words the banner uses.
    static let credentialAccessDenied = "After this update, Silo's engine needs your permission to use its saved credentials."

    /// Whether a message the app shows came from that refusal. Errors reach the pages as text, whether the call or a job failed.
    static func isCredentialAccessDenied(_ message: String?) -> Bool {
        message?.contains(credentialAccessDenied) == true
    }
}

extension ComputersModel {
    /// True once the engine says items are blocked, or any error the page shows is the Keychain refusal.
    var keychainNeedsPermission: Bool {
        keychain.deniedCount > 0 || EngineErrorText.isCredentialAccessDenied(error)
            || EngineErrorText.isCredentialAccessDenied(actionError)
    }

    func refreshKeychainStatus() async {
        await keychain.refresh(using: client)
    }

    /// The banner's button: the engine allows Keychain prompts for this one call and macOS shows its dialogs.
    func repairKeychainAccess() async {
        let usable = await keychain.repair(using: client)
        if usable { clearCredentialRefusal() }
    }
}

/// Shown on the Computers page and in Settings while the engine is refused its saved credentials.
struct KeychainAccessBanner: View {
    let model: ComputersModel

    var body: some View {
        if model.keychainNeedsPermission {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "key.fill").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CDS.Text.warning).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(EngineErrorText.credentialAccessDenied)
                            .font(CDS.sans(12, .medium)).foregroundStyle(CDS.Text.primary)
                        Text("Press Allow access. macOS then asks once for each saved item: choose Always Allow in each dialog.")
                            .font(CDS.sans(11)).foregroundStyle(CDS.Text.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if model.keychain.isRepairing { ProgressView().controlSize(.small) }
                    ActionButton(model.keychain.isRepairing ? "Waiting for macOS…" : "Allow access") {
                        Task { await model.repairKeychainAccess() }
                    }
                    .disabled(model.keychain.isRepairing)
                }
                if let blocked = model.keychain.stillBlocked {
                    Text(blocked).font(CDS.sans(11)).foregroundStyle(CDS.Text.warning)
                }
                if let failure = model.keychain.failure {
                    Text("The repair didn't finish. \(failure)").font(CDS.sans(11)).foregroundStyle(CDS.Text.danger)
                }
            }
            .padding(14)
            .background(CDS.Surface.s2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Keychain access needed")
        }
    }
}
