import Foundation

/// Samples the guest clock through its installed Node runtime. The monotonic midpoint bounds transport latency without
/// comparing an SSH guest's wall clock directly with this Mac's.
enum GuestClock {
    static func sampleMilliseconds(client: any GuestClient, computer: GuestReference) async throws -> Int64 {
        let account = try await client.account(for: computer)
        return try await sampleMilliseconds(client: client, computer: computer, account: account)
    }

    static func sampleMilliseconds(client: any GuestClient, computer: GuestReference, account: GuestAccount) async throws -> Int64 {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try await client.exec(GuestExecRequest(computer: computer,
            argv: [account.nodeExecutable, "-e", "process.stdout.write(String(Date.now()))"],
            cwd: account.home, timeoutSeconds: 3))
        let end = DispatchTime.now().uptimeNanoseconds
        guard result.succeeded, let text = String(data: result.stdout, encoding: .utf8),
              let milliseconds = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw GuestClientFailure.unavailable("Couldn't sample the guest clock with its installed Node runtime")
        }
        return milliseconds + Int64((end - start) / 2_000_000)
    }

    static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}
