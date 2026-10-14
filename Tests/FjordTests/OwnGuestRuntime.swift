import Testing
@testable import Fjord

/// Gives each test of a suite its own guest Router runtime and its own record of which computers a run is on. `GuestRouterRuntime.shared` is process-wide, and suites run side
/// by side (`.serialized` orders only what is inside one), and so are the computers a run holds, keyed alike across suites: another suite switching the Router off, or stopping the guest
/// watchers, would cancel a test's watchers and clear its refresh hook in the middle of it.
struct OwnGuestRuntime: TestTrait, SuiteTrait, TestScoping {
    let isRecursive = true

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        guard testCase != nil else { return try await function() }
        let runtime = await MainActor.run { GuestRouterRuntime() }
        let registry = await MainActor.run { ComputerRunCoordinator.Registry() }
        try await ComputerRunCoordinator.Registry.$scoped.withValue(registry) {
            try await GuestRouterRuntime.$scoped.withValue(runtime, operation: function)
        }
    }
}

extension Trait where Self == OwnGuestRuntime {
    static var ownGuestRuntime: Self { Self() }
}
