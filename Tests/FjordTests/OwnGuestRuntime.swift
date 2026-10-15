import Testing
@testable import Fjord

/// Gives each test of a suite its own guest Router runtime. `GuestRouterRuntime.shared` is process-wide, and suites run side
/// by side (`.serialized` orders only what is inside one): another suite switching the Router off, or stopping the guest
/// watchers, would cancel a test's watchers and clear its refresh hook in the middle of it.
struct OwnGuestRuntime: TestTrait, SuiteTrait, TestScoping {
    let isRecursive = true

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        guard testCase != nil else { return try await function() }
        let runtime = await MainActor.run { GuestRouterRuntime() }
        try await GuestRouterRuntime.$scoped.withValue(runtime, operation: function)
    }
}

extension Trait where Self == OwnGuestRuntime {
    static var ownGuestRuntime: Self { Self() }
}
