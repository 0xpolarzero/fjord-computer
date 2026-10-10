import AppKit
import Testing
@testable import Lookout

/// What the idle gate reads from the app: the sessions, how many work, whether a window shows and whether Reduce Motion is
/// on (a measurement of a bar standing still would pass for free).
@MainActor
@Suite(.hostsWindows) struct LifecycleReport {
    @Test func theLifecycleReportIsTheLineTheIdleScriptReads() {
        let store = Store()
        store.persists = false
        let line = Lifecycle.line(store)
        let pattern = #"^lifecycle: sessions=\d+ working=\d+ showing=[01] reduceMotion=[01]\n$"#
        #expect(line.range(of: pattern, options: .regularExpression) != nil, "\(line)")
    }
}
