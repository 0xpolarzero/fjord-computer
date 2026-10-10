import Foundation
import Testing
@testable import Lookout

@MainActor
@Suite struct CI {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func check(_ name: String, _ status: String = "completed", _ conclusion: String? = "success", started: TimeInterval = 0,
                       completed: TimeInterval? = nil, app: String? = "circleci", suite: Int? = nil) -> GHCheckRuns.Run {
        GHCheckRuns.Run(app: GHCheckRuns.App(slug: app), checkSuite: suite.map(GHCheckRuns.Suite.init), name: name, status: status, conclusion: conclusion, headSha: "s",
                        startedAt: t0.addingTimeInterval(started), completedAt: completed.map { t0.addingTimeInterval($0) })
    }

    private func combined(_ statuses: [GHCombinedStatus.Status] = []) -> GHCombinedStatus {
        GHCombinedStatus(state: "success", totalCount: statuses.count, sha: "s", statuses: statuses)
    }

    // MARK: Reading GitHub's answer

    @Test func aRepoWithOnlyExternalChecksHasAStateNamesAndAChangeTime() {
        let failed = Store.readCI(runs: [], sha: nil, checks: [check("build", "completed", "failure", started: 10, completed: 90),
                                                                check("lint", started: 5, completed: 40)], combined: combined())
        #expect(failed.state == .failure)
        #expect(failed.failing == ["build"])
        #expect(failed.changedAt == t0.addingTimeInterval(90))
        let running = Store.readCI(runs: [], sha: nil, checks: [check("build", "in_progress", nil, started: 30)], combined: combined())
        #expect(running.state == .pending)
        // Still running: it last changed when it started.
        #expect(running.changedAt == t0.addingTimeInterval(30))
    }

    @Test func aRepoWithOnlyLegacyStatusesHasAChangeTime() {
        let status = GHCombinedStatus.Status(context: "ci/jenkins", state: "failure", createdAt: t0, updatedAt: t0.addingTimeInterval(20))
        let reading = Store.readCI(runs: [], sha: nil, checks: [], combined: combined([status]))
        #expect(reading.state == .failure && reading.failing == ["ci/jenkins"] && reading.changedAt == t0.addingTimeInterval(20))
        let neverUpdated = GHCombinedStatus.Status(context: "ci/x", state: "success", createdAt: t0, updatedAt: nil)
        #expect(Store.readCI(runs: [], sha: nil, checks: [], combined: combined([neverUpdated])).changedAt == t0)
    }

    @Test func theLatestChangeAmongActionsAndExternalSourcesWins() {
        let run = GHWorkflowRuns.Run(name: "build", workflowId: 1, headSha: "s", displayTitle: "Fix", updatedAt: t0.addingTimeInterval(50),
                                     status: "completed", conclusion: "success", checkSuiteId: 10)
        let other = GHWorkflowRuns.Run(name: "old", workflowId: 2, headSha: "older", displayTitle: nil, updatedAt: t0.addingTimeInterval(500),
                                       status: "completed", conclusion: "failure", checkSuiteId: 20)
        // A github-actions check run is the Actions run again, not an external source.
        let mirror = check("build", started: 0, completed: 900, app: "github-actions")
        let external = check("deploy", started: 10, completed: 70)
        let reading = Store.readCI(runs: [run, other], sha: "s", checks: [mirror, external], combined: combined())
        #expect(reading.state == .success)
        #expect(reading.changedAt == t0.addingTimeInterval(70))
        let nothing = Store.readCI(runs: [], sha: nil, checks: [], combined: combined())
        #expect(nothing.state == .none && nothing.failing.isEmpty && nothing.changedAt == nil && nothing.workflows.isEmpty)
    }

    private func workflow(_ name: String, id: Int, suite: Int?, _ conclusion: String?, sha: String = "s",
                          status: String = "completed") -> GHWorkflowRuns.Run {
        GHWorkflowRuns.Run(name: name, workflowId: id, headSha: sha, displayTitle: "Fix", updatedAt: t0, status: status,
                           conclusion: conclusion, checkSuiteId: suite)
    }

    @Test func aFailedWorkflowIsNamedByItsFailedJobs() {
        let ci = workflow("CI", id: 1, suite: 10, "failure")
        let jobs = [check("Linux build", "completed", "failure", app: "github-actions", suite: 10),
                    check("macOS test", "completed", "success", app: "github-actions", suite: 10),
                    check("Windows test", "completed", "timed_out", app: "github-actions", suite: 10)]
        let reading = Store.readCI(runs: [ci], sha: "s", checks: jobs, combined: combined())
        #expect(reading.state == .failure)
        #expect(reading.failing == ["Linux build", "Windows test"])
    }

    @Test func aFailedWorkflowWithNoJobsKeepsItsOwnName() {
        let ci = workflow("CI", id: 1, suite: 10, "failure")
        // No job at all, a job of another suite, and a job with no suite known.
        #expect(Store.readCI(runs: [ci], sha: "s", checks: [], combined: combined()).failing == ["CI"])
        let elsewhere = [check("Other", "completed", "failure", app: "github-actions", suite: 99)]
        #expect(Store.readCI(runs: [ci], sha: "s", checks: elsewhere, combined: combined()).failing == ["CI"])
        let unknown = workflow("CI", id: 1, suite: nil, "failure")
        let job = [check("Linux build", "completed", "failure", app: "github-actions")]
        #expect(Store.readCI(runs: [unknown], sha: "s", checks: job, combined: combined()).failing == ["CI"])
    }

    @Test func jobsOfRunsThatDoNotCountAreLeftOut() {
        // A failed job of a workflow run the push's selection didn't take (another trigger, an older run) says nothing.
        let ci = workflow("CI", id: 1, suite: 10, "success")
        let stray = [check("Triage", "completed", "failure", app: "github-actions", suite: 30)]
        #expect(Store.readCI(runs: [ci], sha: "s", checks: stray, combined: combined()).state == .success)
    }

    @Test func actionsJobsAndExternalChecksFailTogether() {
        let ci = workflow("CI", id: 1, suite: 10, "failure")
        let checks = [check("Linux build", "completed", "failure", app: "github-actions", suite: 10),
                      check("deploy", "completed", "failure")]
        let reading = Store.readCI(runs: [ci], sha: "s", checks: checks, combined: combined())
        #expect(reading.failing == ["Linux build", "deploy"])
    }

    @Test func theSuiteLinksAJobToItsWorkflowRunInGitHubsJSON() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let job = try decoder.decode(GHCheckRuns.Run.self, from: Data(
            #"{"name":"Linux build","status":"completed","conclusion":"failure","head_sha":"s","app":{"slug":"github-actions"},"check_suite":{"id":10}}"#.utf8))
        let run = try decoder.decode(GHWorkflowRuns.Run.self, from: Data(
            #"{"name":"CI","workflow_id":1,"head_sha":"s","status":"completed","conclusion":"failure","check_suite_id":10}"#.utf8))
        #expect(job.checkSuite?.id == 10 && run.checkSuiteId == 10)
    }

    @Test func aCommitsHeadlineIsItsFirstLine() throws {
        let decoder = JSONDecoder()
        let commit = try decoder.decode(GHCommit.self, from: Data(#"{"commit":{"message":"Respect trailing commas (#1042)\n\nLong body"}}"#.utf8))
        #expect(commit.headline == "Respect trailing commas (#1042)")
    }

    @Test func aHeadlineIsOnlyAskedForWhenTheRunHasNone() async {
        let store = Store()
        store.persists = false
        #expect(await store.ciHeadline("a/x", commit: "c1", runTitle: "From the run") == "From the run")
        store.headlines["a/x"] = ("c1", "Known")
        // Same commit as last time: what was fetched then stands (no request).
        #expect(await store.ciHeadline("a/x", commit: "c1", runTitle: nil) == "Known")
    }

    // MARK: Per workflow

    @Test func eachWorkflowHasItsOwnStateAndFailedJobs() {
        let ci = workflow("CI", id: 1, suite: 10, "failure")
        let lint = workflow("Lint", id: 2, suite: 20, "success")
        let docs = workflow("Docs", id: 3, suite: 30, nil, status: "in_progress")
        let jobs = [check("Linux build", "completed", "failure", app: "github-actions", suite: 10),
                    check("Windows test", "completed", "failure", app: "github-actions", suite: 10)]
        let reading = Store.readCI(runs: [ci, lint, docs], sha: "s", checks: jobs, combined: combined())
        // By name: CI, Docs, Lint.
        #expect(reading.workflows.map(\.name) == ["CI", "Docs", "Lint"])
        #expect(reading.workflows.map(\.id) == ["1", "3", "2"])
        #expect(reading.workflows.map(\.state) == [.failure, .pending, .success])
        #expect(reading.workflows[0].failing == ["Linux build", "Windows test"])
        #expect(reading.workflows[1].failing.isEmpty && reading.workflows[2].failing.isEmpty)
        // The whole is what it always was.
        #expect(reading.state == .failure && reading.failing == ["Linux build", "Windows test"])
    }

    @Test func externalChecksAndStatusesAreOneWorkflowOfTheirOwn() {
        let status = GHCombinedStatus.Status(context: "ci/jenkins", state: "failure", createdAt: t0, updatedAt: t0.addingTimeInterval(20))
        let ci = workflow("CI", id: 1, suite: 10, "success")
        let reading = Store.readCI(runs: [ci], sha: "s", checks: [check("deploy", "completed", "failure", started: 1, completed: 30)],
                                   combined: combined([status]))
        #expect(reading.workflows.map(\.id) == ["1", Store.externalWorkflowID])
        let external = reading.workflows[1]
        #expect(external.state == .failure && external.failing == ["deploy", "ci/jenkins"])
        #expect(external.updatedAt == t0.addingTimeInterval(30))
        // Nothing external, nothing to say about it.
        #expect(Store.readCI(runs: [ci], sha: "s", checks: [], combined: combined()).workflows.map(\.id) == ["1"])
    }

    @Test func aBranchIsReadWorkflowByWorkflowFromOneListOfRuns() async throws {
        let store = Store()
        store.persists = false
        store.me = GHUser(login: "me", avatarUrl: nil, type: "User")
        let paths = PathLog()
        store.gh.session = StubbedGitHub.session { request in
            let path = request.url?.path ?? ""
            paths.add(path)
            switch path {
            case "/repos/a/x/actions/runs":
                return .init(200, #"""
                {"workflow_runs":[
                  {"name":"CI","workflow_id":11,"head_sha":"s1","display_title":"Fix","status":"completed","conclusion":"failure","check_suite_id":5,"html_url":"https://github.com/a/x/actions/runs/1"},
                  {"name":"Lint","workflow_id":12,"head_sha":"s1","display_title":"Fix","status":"completed","conclusion":"success","check_suite_id":6},
                  {"name":"CI","workflow_id":11,"head_sha":"s0","display_title":"Older","status":"completed","conclusion":"success","check_suite_id":4}]}
                """#)
            case "/repos/a/x/commits/s1/check-runs":
                return .init(200, #"""
                {"total_count":1,"check_runs":[{"name":"build","status":"completed","conclusion":"failure","head_sha":"s1","app":{"slug":"github-actions"},"check_suite":{"id":5}}]}
                """#)
            case "/repos/a/x/commits/s1/status":
                return .init(200, #"{"state":"success","total_count":0,"sha":"s1","statuses":[]}"#)
            default:
                return .init(404, #"{"message":"unrouted"}"#)
            }
        }
        let status = try await store.fetchBranchCI("a/x", branch: "main")
        #expect(status.state == .failure && status.failing == ["build"] && status.title == "Fix")
        #expect(status.workflows.map(\.name) == ["CI", "Lint"])
        #expect(status.workflows.map(\.state) == [.failure, .success])
        #expect(status.workflows[0].url?.absoluteString == "https://github.com/a/x/actions/runs/1")
        // One list of runs, the commit's checks and statuses: three calls for the repo, however many workflows.
        #expect(paths.all.count == 3)
        let things = InboxSync.workflowThings(repo: "a/x", branch: "main", status: status)
        #expect(things.map(\.id) == ["workflow:a/x:11@main", "workflow:a/x:12@main"])
    }
}

/// Paths a stub was asked for, from whichever thread it answers on.
private final class PathLog: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    func add(_ path: String) { lock.withLock { paths.append(path) } }
    var all: [String] { lock.withLock { paths } }
}

@Suite struct FailingChecks {
    @Test func theChipNamesTheFailingChecksAndCountsTheRest() {
        #expect(FailingNames.summary(["build"]) == "build")
        #expect(FailingNames.summary(["build", "lint"]) == "build, lint")
        #expect(FailingNames.summary(["build", "lint", "test", "deploy"]) == "build, lint +2")
    }

    @Test func aLongNameIsCutShort() {
        #expect(FailingNames.summary(["Linux build (release, arm64)"]) == "Linux build (re…")
        #expect(FailingNames.summary(["exactly sixteen!"]) == "exactly sixteen!")
    }
}
