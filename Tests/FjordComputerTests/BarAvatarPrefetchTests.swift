import AppKit
import Testing
@testable import FjordComputer

extension WindowSeams {
    @MainActor
    @Suite(.hostsWindows) struct BarAvatarPrefetch {
        @Test func avatarsWaitForAFrameAfterTheHubOpensAndSkipAHubThatClosed() {
            _ = NSApplication.shared
            let saved = (AppTransition.nextTurn, AppTransition.nextFrames)
            var turns: [@MainActor () -> Void] = []
            var frames: [@MainActor () -> Void] = []
            AppTransition.nextTurn = { turns.append($0) }
            AppTransition.nextFrames = { _, _, block in frames.append(block) }
            defer {
                AppTransition.nextTurn = saved.0
                AppTransition.nextFrames = saved.1
            }
            let store = Store()
            store.persists = false
            Demo.populate(store, .router)
            let controller = HubController(store: store, demo: true)
            var warmed: [[URL]] = []
            controller.prefetchAvatars = { warmed.append($0) }
            controller.setWindowOpen(true)
            #expect(turns.count == 1 && frames.isEmpty && warmed.isEmpty)
            // The existing turn after the morph still reports opening to the store before requesting a frame.
            turns.removeFirst()()
            #expect(frames.count == 1 && warmed.isEmpty)
            store.me = GHUser(login: "me", avatarUrl: URL(string: "https://example.invalid/new-avatar"), type: "User")
            let expected = store.avatarsToWarm(first: controller.hub.tab)
            frames.removeFirst()()
            #expect(warmed == [expected])
            controller.setWindowOpen(false)
            controller.setWindowOpen(true)
            turns.removeFirst()()
            #expect(frames.count == 1 && warmed.count == 1)
            controller.setWindowOpen(false)
            frames.removeFirst()()
            #expect(warmed.count == 1)
            controller.setWindowOpen(true)
        }

        /// While the window's morph plays, the bar tells the store nothing and warms no avatar: both go once it has played.
        @Test func theStoreAndTheAvatarsWaitForTheMorph() async {
            _ = NSApplication.shared
            let saved = (AppTransition.nextTurn, AppTransition.nextFrames)
            var turns: [@MainActor () -> Void] = []
            var frames: [@MainActor () -> Void] = []
            AppTransition.nextTurn = { turns.append($0) }
            AppTransition.nextFrames = { _, _, block in frames.append(block) }
            defer {
                AppTransition.nextTurn = saved.0
                AppTransition.nextFrames = saved.1
                MotionGate.ended()
            }
            let store = Store()
            store.persists = false
            Demo.populate(store, .router)
            let controller = HubController(store: store, demo: true)
            var warmed: [[URL]] = []
            controller.prefetchAvatars = { warmed.append($0) }
            MotionGate.began()
            controller.setWindowOpen(true)
            turns.removeFirst()()
            try? await Task.sleep(for: .milliseconds(20))
            #expect(frames.isEmpty && warmed.isEmpty)
            MotionGate.ended()
            await waitUntil { frames.count == 1 }
            frames.removeFirst()()
            await waitUntil { warmed.count == 1 }
            #expect(warmed.count == 1)
            controller.setWindowOpen(false)
        }
    }
}
