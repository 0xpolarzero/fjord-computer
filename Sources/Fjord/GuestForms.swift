import Foundation

struct GuestFormKey: Codable, Hashable, Sendable {
    var location: SessionLocation
    var cliSessionID: String
}

struct GuestPendingForm: Codable, Equatable, Sendable {
    var computer: GuestReference
    var location: SessionLocation
    var form: PendingForm
}

struct GuestFormsSnapshot: Sendable {
    var watch: GuestFilesWatch
    var forms: [GuestFormKey: GuestPendingForm]
}

/// Reads and answers guest forms with guest.files only. PID checks are issued to the guest; the same numeric PID on the
/// controller is irrelevant.
struct GuestForms: Sendable {
    var client: any GuestClient

    func watch(computer: GuestReference, paths: GuestRouterPaths) async throws -> GuestFormsSnapshot {
        let subscription = try await client.filesWatch(computer: computer, paths: [paths.forms])
        let forms = try await read(computer: computer, paths: paths)
        return GuestFormsSnapshot(watch: subscription, forms: forms)
    }

    func read(computer: GuestReference, paths: GuestRouterPaths) async throws -> [GuestFormKey: GuestPendingForm] {
        do { _ = try await client.filesRead(computer: computer, path: GuestRouterPaths.join(paths.forms, FormBridge.marker), offset: nil, length: nil) }
        catch GuestClientFailure.notFound(_) { return [:] }

        let entries: [GuestFileEntry]
        do { entries = try await client.filesList(computer: computer, path: paths.forms) }
        catch GuestClientFailure.notFound(_) { return [:] }
        let location = SessionLocation.computer(deviceId: computer.deviceId, computerId: computer.computerId)
        var forms: [GuestFormKey: GuestPendingForm] = [:]
        var expired: [String] = []
        for entry in entries where entry.type == .file && entry.name.hasSuffix(".json") && !entry.name.hasPrefix(".")
            && !entry.name.hasSuffix(".answer.json") {
            let path = GuestRouterPaths.join(paths.forms, entry.name)
            guard let data = try? await client.filesRead(computer: computer, path: path, offset: nil, length: nil).data,
                  let form = PendingForm.decode(data) else { continue }
            switch try await processState(computer: computer, form: form) {
            case .dead:
                expired.append(path)
                expired.append(GuestRouterPaths.join(paths.forms, "\(form.id).answer.json"))
            case .alive, .unknown:
                let key = GuestFormKey(location: location, cliSessionID: form.cliSessionID)
                if let other = forms[key], other.form.createdAt > form.createdAt { continue }
                forms[key] = GuestPendingForm(computer: computer, location: location, form: form)
            }
        }
        if !expired.isEmpty { _ = try await client.filesRemove(computer: computer, paths: expired) }
        return forms
    }

    func answer(_ guestForm: GuestPendingForm, answers: [String: String],
                stillValid: @escaping @MainActor @Sendable () async -> Bool = { true }) async throws {
        let data = try FormBridge.answerData(guestForm.form, answers)
        try await writeAnswer(guestForm, data: data, stillValid: stillValid)
    }

    func answer(_ guestForm: GuestPendingForm, plan decision: PendingForm.PlanDecision,
                stillValid: @escaping @MainActor @Sendable () async -> Bool = { true }) async throws {
        let data = try FormBridge.answerData(guestForm.form, plan: decision)
        try await writeAnswer(guestForm, data: data, stillValid: stillValid)
    }

    private func writeAnswer(_ guestForm: GuestPendingForm, data: Data,
                             stillValid: @escaping @MainActor @Sendable () async -> Bool) async throws {
        guard await stillValid() else { throw FormWriter.Cancelled() }
        let paths = try GuestRouterPaths(home: try await client.account(for: guestForm.computer).home)
        let path = GuestRouterPaths.join(paths.forms, "\(guestForm.form.id).answer.json")
        do {
            try await client.filesWrite(GuestFileWriteRequest(computer: guestForm.computer, path: path, data: data,
                                                              mode: 0o600, createParents: true, replace: .never))
        } catch GuestClientFailure.exists {
            throw FormWriter.AlreadyAnswered()
        }
    }

    private enum ProcessState { case alive, dead, unknown }

    private func processState(computer: GuestReference, form: PendingForm) async throws -> ProcessState {
        guard form.pid > 0 else { return .dead }
        do {
            let account = try await client.account(for: computer)
            let result = try await client.exec(GuestExecRequest(computer: computer, argv: ["/bin/kill", "-0", String(form.pid)],
                                                                cwd: account.home, timeoutSeconds: 2))
            if result.succeeded { return .alive }
            let error = String(decoding: result.stderr, as: UTF8.self).lowercased()
            if error.contains("permission") || error.contains("operation not permitted") { return .unknown }
            return .dead
        } catch GuestClientFailure.permissionDenied(_) { return .unknown }
    }
}
