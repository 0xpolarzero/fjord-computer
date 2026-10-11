import Foundation
import Testing
@testable import Lookout

@MainActor
@Suite struct ToolsTests {
    private func store() -> Store {
        let s = Store()
        s.persists = false
        return s
    }

    @Test func noToolIsOnUntilOneIsSwitchedOn() {
        let s = store()
        #expect(s.tools.isEmpty)
        #expect(s.settings.toolsPicked == nil)
        s.setTool(.triage, on: true)
        #expect(s.tools == [.triage])
        #expect(!s.toolsLinked)
    }

    @Test func withTriageOffGitHubIsNotChecked() {
        let s = store()
        s.refreshNow()
        #expect(!s.isSyncing)
        s.setHubOpen(true)
        #expect(!s.isSyncing)
    }

    @Test func withTriageOffNoAvatarIsWarmed() {
        let s = store()
        Demo.populate(s, .busy)
        #expect(!s.avatarsToWarm().isEmpty)
        s.setTool(.triage, on: false)
        #expect(s.avatarsToWarm().isEmpty)
    }

    @Test func switchingTriageOffStopsTheInboxTimerAndChecksNothingMore() async {
        let s = store()
        Demo.populate(s, .busy)
        s.inboxMemo.timer = Task {}
        s.setTool(.triage, on: false)
        #expect(s.inboxMemo.timer == nil)
        let last = s.lastSync
        await s.pollAll()
        #expect(s.lastSync == last)
    }

    @Test func withTriageOffTheWindowOpensOnTheRouter() {
        let s = store()
        Demo.populate(s, .busy)
        #expect(s.firstPlace != .router)
        s.setTool(.triage, on: false)
        #expect(s.firstPlace == .router)
    }

    @Test func eachShortcutBelongsToItsTool() {
        #expect(ShortcutAction.togglePanel.tool == nil)
        #expect(ShortcutAction.router.tool == .router)
        for action in [ShortcutAction.openItem, .toggleRead, .discard, .markAllRead, .refresh] { #expect(action.tool == .triage) }
    }
}
