import Testing
@testable import Fjord

@Suite struct MotionScriptParsing {
    /// The steps in order, then a count (once when there is none).
    @Test func readsStepsAndCount() {
        #expect(MotionScript("open,close,fold,peek,drag x20") == MotionScript(steps: [.open, .close, .fold, .peek, .drag], count: 20))
        #expect(MotionScript("peek") == MotionScript(steps: [.peek], count: 1))
        #expect(MotionScript("open,open x1") == MotionScript(steps: [.open, .open], count: 1))
        #expect(MotionScript("fold x1000")?.count == 1000)
    }

    @Test func refusesWhatIsNotAScript() {
        for text in ["", " ", "jump", "open,jump", "open,,close", ",open", "open,", "Open", "open, close", "open x", "open x0",
                     "open x-1", "open x+3", "open x1001", "open 20", "open x20 x2", "open x2.5"] {
            #expect(MotionScript(text) == nil, "\(text)")
        }
    }

    /// The steps and the count as one argument or two; nothing without the flag; the flag with no script is an error.
    @Test func readsTheArguments() throws {
        let one = try MotionScript.parse(arguments: ["app", "--demo", "busy", "--motion-script", "open,close x3", "--quit-after"])
        let two = try MotionScript.parse(arguments: ["app", "--motion-script", "open,close", "x3", "--quit-after"])
        #expect(one == MotionScript(steps: [.open, .close], count: 3))
        #expect(two == one)
        #expect(try MotionScript.parse(arguments: ["app", "--motion-script", "fold", "--quit-after"]) == MotionScript(steps: [.fold]))
        #expect(try MotionScript.parse(arguments: ["app", "--demo", "busy"]) == nil)
        #expect(throws: MotionScript.Problem.self) { try MotionScript.parse(arguments: ["app", "--motion-script"]) }
        #expect(throws: MotionScript.Problem.self) { try MotionScript.parse(arguments: ["app", "--motion-script", "--quit-after"]) }
        #expect(throws: MotionScript.Problem.self) { try MotionScript.parse(arguments: ["app", "--motion-script", "open", "x0"]) }
    }

    /// The whole list, `count` times over.
    @Test func playsTheListCountTimes() {
        #expect(MotionScript(steps: [.open, .close], count: 2).played == [.open, .close, .open, .close])
    }
}
