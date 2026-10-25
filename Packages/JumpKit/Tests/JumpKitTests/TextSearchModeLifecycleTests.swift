import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import JumpKit

/// Records the jumps text search mode performs.
final class JumpLog: Sendable {
    let entries = Mutex<[String]>([])
    func record(_ action: HintAction, _ match: TextMatch<ModeNode>) {
        let frame = match.frame
        entries.withLock {
            $0.append("\(action) \(match.run.node.id) \(match.range.location)+\(match.range.length) at \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
        }
    }
}

@Suite("TextSearchMode lifecycle")
struct TextSearchModeLifecycleTests {
    let overlay = FakeSearchOverlay()
    let input = FakeInput()
    let jumps = JumpLog()

    private static let window = CGRect(x: 0, y: 0, width: 800, height: 600)

    /// Reading order: "save" (top left), "sale" (top right), "salad" (below).
    private static let runs = [
        TextRun(text: "salad", frame: CGRect(x: 10, y: 100, width: 100, height: 20), role: "AXStaticText",
                isEditable: false, node: ModeNode(id: "salad")),
        TextRun(text: "sale", frame: CGRect(x: 200, y: 10, width: 100, height: 20), role: "AXButton",
                isEditable: false, node: ModeNode(id: "sale")),
        TextRun(text: "save", frame: CGRect(x: 10, y: 10, width: 100, height: 20), role: "AXStaticText",
                isEditable: false, node: ModeNode(id: "save")),
    ]

    /// Word bounds: 10 points per UTF-16 unit from the run's origin.
    private static func wordFrame(_ match: TextMatch<ModeNode>) -> CGRect {
        CGRect(x: match.run.frame.minX + CGFloat(match.range.location) * 10, y: match.run.frame.minY,
               width: CGFloat(match.range.length) * 10, height: 20)
    }

    private func makeMode(
        trusted: Bool = true,
        frontmost: FrontmostApp? = fakeApp,
        prepareApp: @escaping (FrontmostApp) async -> Void = { _ in },
        windowFrame: @escaping TextSearchMode<ModeNode>.WindowFrameReader = { _ in window },
        collect: @escaping TextSearchMode<ModeNode>.Collector = { _ in runs },
        locate: @escaping TextSearchMode<ModeNode>.Locator = { wordFrame($0) }
    ) -> TextSearchMode<ModeNode> {
        let jumps = self.jumps
        return TextSearchMode(
            overlay: overlay, input: input, isTrusted: { trusted }, frontmostApp: { frontmost },
            prepareApp: prepareApp, windowFrame: windowFrame, collect: collect, locate: locate,
            perform: { action, match in jumps.record(action, match) }
        )
    }

    /// Opens the box and waits for the text.
    private func open(_ mode: TextSearchMode<ModeNode>) async {
        mode.toggle()
        await mode.scanTask?.value
    }

    private func settle(_ mode: TextSearchMode<ModeNode>) async {
        await mode.locateTask?.value
    }

    private func performed(_ mode: TextSearchMode<ModeNode>) async -> [String] {
        await mode.actionTask?.value
        return jumps.entries.withLock { $0 }
    }

    private func type(_ text: String) {
        input.type(text, keyCode: 0)
    }

    private func tab(shift: Bool = false) {
        input.type("\t", keyCode: 48, shift: shift)
    }

    // MARK: Opening

    @Test func showsTheBoxBeforeTheTextIsCollected() async {
        let gate = Gate()
        let mode = makeMode(collect: { _ in
            await gate.pass()
            return Self.runs
        })
        mode.toggle()
        await gate.reached()
        #expect(overlay.presentations == [
            SearchPresentation(query: "", status: .collecting, matches: [], windowFrame: Self.window),
        ])
        #expect(mode.isActive)
        #expect(input.isListening)
        #expect(input.target == fakeApp)

        gate.open()
        await mode.scanTask?.value
        #expect(overlay.last == SearchPresentation(query: "", status: .idle, matches: [], windowFrame: Self.window))
        #expect(mode.lastSummary?.hasPrefix("Target: 3 texts in ") == true)
    }

    @Test func preparesTheAppBeforeCollecting() async {
        let log = CallLog()
        let mode = makeMode(
            prepareApp: { app in log.calls.withLock { $0.append("prepare \(app.pid)") } },
            collect: { app in
                log.calls.withLock { $0.append("collect \(app.pid)") }
                return Self.runs
            }
        )
        await open(mode)
        #expect(log.calls.withLock { $0 } == ["prepare 42", "collect 42"])
    }

    @Test func explainsWhenAccessibilityAccessIsMissing() async {
        let mode = makeMode(trusted: false)
        await open(mode)
        #expect(mode.lastSummary == "Accessibility access required")
        #expect(overlay.presentations.isEmpty)
    }

    @Test func doesNotSearchJUMPItself() async {
        let mode = makeMode(frontmost: nil)
        await open(mode)
        #expect(mode.lastSummary == "No app to search")
        #expect(overlay.presentations.isEmpty)
    }

    @Test func reportsAWindowlessApp() async {
        struct NoWindow: Error {}
        let mode = makeMode(windowFrame: { _ in throw NoWindow() })
        await open(mode)
        #expect(mode.lastSummary == "Target: no focused window")
        #expect(overlay.presentations.isEmpty)
        #expect(!input.isListening)
        #expect(!mode.isActive)
    }

    @Test func leavesWhenTheBoxCannotTakeTheKeyboard() async {
        let collected = CallLog()
        overlay.canTakeKeyboard = false
        let mode = makeMode(collect: { _ in
            collected.calls.withLock { $0.append("collect") }
            return Self.runs
        })
        await open(mode)
        #expect(!mode.isActive)
        #expect(!input.isListening)
        #expect(!overlay.isVisible)
        #expect(collected.calls.withLock { $0 }.isEmpty)
    }

    // MARK: Matching

    @Test func typingBeforeTheTextArrivesMatchesOnceItDoes() async {
        let gate = Gate()
        let mode = makeMode(collect: { _ in
            await gate.pass()
            return Self.runs
        })
        mode.toggle()
        await gate.reached()
        type("sa")
        #expect(overlay.last == SearchPresentation(query: "sa", status: .collecting, matches: [], windowFrame: Self.window))

        gate.open()
        await mode.scanTask?.value
        await settle(mode)
        #expect(overlay.last == SearchPresentation(
            query: "sa", status: .matches(selected: 0),
            matches: [CGRect(x: 10, y: 10, width: 20, height: 20), CGRect(x: 200, y: 10, width: 20, height: 20),
                      CGRect(x: 10, y: 100, width: 20, height: 20)],
            windowFrame: Self.window
        ))
    }

    @Test func showsRunFramesUntilWordBoundsArrive() async {
        let mode = makeMode()
        await open(mode)
        type("v")
        #expect(overlay.last?.matches == [Self.runs[2].frame])
        await settle(mode)
        #expect(overlay.last?.matches == [CGRect(x: 30, y: 10, width: 10, height: 20)])
    }

    @Test func reportsNoMatchesAndAnEmptyQuery() async {
        let mode = makeMode()
        await open(mode)
        type("x")
        #expect(overlay.last?.status == .noMatches)
        #expect(overlay.last?.matches == [])
        input.press(keyCode: 51)
        #expect(overlay.last?.status == .idle)
        #expect(overlay.last?.query == "")
    }

    @Test func staleWordBoundsAreIgnored() async {
        let gate = Gate()
        // Only the one-letter query's lookup is slow.
        let mode = makeMode(locate: { match in
            if match.range.length == 1 {
                await gate.pass()
                return CGRect(x: 999, y: 999, width: 1, height: 1)
            }
            return Self.wordFrame(match)
        })
        await open(mode)
        type("v")
        await gate.reached()
        let staleLookup = mode.locateTask
        type("e")
        await settle(mode)
        gate.open()
        await staleLookup?.value
        #expect(overlay.last?.query == "ve")
        #expect(overlay.last?.matches == [CGRect(x: 30, y: 10, width: 20, height: 20)])
    }

    // MARK: Navigating

    @Test func tabMovesThroughMatchesAndWraps() async {
        let mode = makeMode()
        await open(mode)
        type("sa")
        #expect(overlay.last?.status == .matches(selected: 0))
        tab()
        #expect(overlay.last?.status == .matches(selected: 1))
        tab()
        tab()
        #expect(overlay.last?.status == .matches(selected: 0))
        tab(shift: true)
        #expect(overlay.last?.status == .matches(selected: 2))
    }

    @Test func editingTheQueryReturnsToTheFirstMatch() async {
        let mode = makeMode()
        await open(mode)
        type("sa")
        tab()
        type("l")
        #expect(overlay.last?.status == .matches(selected: 0))
    }

    // MARK: Jumping

    @Test(arguments: [
        ("none", "press"), ("shift", "rightClick"), ("command", "doubleClick"), ("option", "moveCursor"),
    ])
    func returnJumpsToTheSelectedMatch(modifier: String, action: String) async {
        let mode = makeMode()
        await open(mode)
        type("sa")
        tab()
        input.type("\r", keyCode: 36, shift: modifier == "shift", command: modifier == "command",
                   option: modifier == "option")
        // Dismissed first, so focus is back in the app when the jump arrives.
        #expect(!mode.isActive)
        #expect(!input.isListening)
        #expect(!overlay.isVisible)
        #expect(await performed(mode) == ["\(action) sale 0+2 at 200,10 20x20"])
    }

    @Test func returnWithoutMatchesDoesNothing() async {
        let mode = makeMode()
        await open(mode)
        type("x")
        input.press(keyCode: 36, characters: "\r")
        #expect(mode.isActive)
        #expect(await performed(mode).isEmpty)
    }

    // MARK: Dismissing

    @Test(arguments: ["escape", "hotkey", "focus left", "keyboard lost"])
    func everyExitHidesTheBoxWithoutJumping(exit: String) async {
        let mode = makeMode()
        await open(mode)
        type("sa")
        switch exit {
        case "escape": input.press(keyCode: 53)
        case "hotkey": mode.toggle()
        case "focus left": input.moveFocusAway()
        default: input.loseKeyboard()
        }
        #expect(!mode.isActive)
        #expect(!input.isListening)
        #expect(!overlay.isVisible)
        #expect(await performed(mode).isEmpty)
    }

    @Test func closingDuringCollectionShowsNothingMore() async {
        let gate = Gate()
        let mode = makeMode(collect: { _ in
            await gate.pass()
            return Self.runs
        })
        mode.toggle()
        await gate.reached()
        let collection = mode.scanTask
        mode.toggle()
        gate.open()
        await collection?.value
        #expect(overlay.presentations.count == 1)
        #expect(overlay.hideCount == 1)
        #expect(!overlay.isVisible)
        #expect(!mode.isActive)
    }

    @Test func theHotkeyAgainOpensANewSearch() async {
        let mode = makeMode()
        await open(mode)
        type("sa")
        mode.toggle()
        await open(mode)
        #expect(mode.isActive)
        #expect(overlay.last == SearchPresentation(query: "", status: .idle, matches: [], windowFrame: Self.window))
    }
}
