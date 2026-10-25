import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import JumpKit

/// Text search with the OCR fallback (`ScreenTextSource`).
@Suite("TextSearchMode screen text")
struct TextSearchModeScreenTextTests {
    let overlay = FakeSearchOverlay()
    let input = FakeInput()
    let jumps = JumpLog()
    let screenJumps = CallLog()
    let recognitions = CallLog()

    private static let window = CGRect(x: 0, y: 0, width: 800, height: 600)

    private static let axRuns = [
        TextRun(text: "save", frame: CGRect(x: 10, y: 10, width: 100, height: 20), role: "AXStaticText",
                isEditable: false, node: ModeNode(id: "save")),
    ]

    /// A recognized line whose words each have a box: 10 points per character.
    private static func line(_ text: String, y: CGFloat) -> TextRun<ScreenText> {
        let words = ScreenTextLayout.wordRanges(in: text).map { range in
            let nsRange = NSRange(range, in: text)
            return ScreenText.Word(range: nsRange, frame: CGRect(x: 20 + CGFloat(nsRange.location) * 10, y: y,
                                                                 width: CGFloat(nsRange.length) * 10, height: 16))
        }
        return TextRun(text: text, frame: CGRect(x: 20, y: y, width: CGFloat(text.utf16.count) * 10, height: 16),
                       role: ScreenTextLayout.role, isEditable: false, node: ScreenText(words: words))
    }

    /// "save" exists in both sources; "status" only on screen.
    private static let screenRuns = [line("git status", y: 300), line("save the status", y: 400)]

    private func makeMode(
        enabled: Bool = true,
        source: Bool = true,
        collect: @escaping TextSearchMode<ModeNode>.Collector = { _ in Self.axRuns },
        recognize: ScreenTextSource.Recognizer? = nil
    ) -> TextSearchMode<ModeNode> {
        let jumps = self.jumps
        let screenJumps = self.screenJumps
        let recognitions = self.recognitions
        let recognize = recognize ?? { _, _ in Self.screenRuns }
        let screenText = ScreenTextSource(
            isEnabled: { enabled },
            recognize: { app, frame in
                recognitions.calls.withLock { $0.append("recognize \(app.pid) \(frame)") }
                return try await recognize(app, frame)
            },
            perform: { action, match in
                let frame = match.frame
                screenJumps.calls.withLock {
                    $0.append("\(action) \(match.run.text) \(match.range.location)+\(match.range.length) at \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
                }
            }
        )
        return TextSearchMode(
            overlay: overlay, input: input, isTrusted: { true }, frontmostApp: { fakeApp },
            windowFrame: { _ in Self.window }, collect: collect, locate: { _ in nil },
            perform: { action, match in jumps.record(action, match) },
            screenText: source ? screenText : nil
        )
    }

    /// Opens the box and waits for both sources.
    private func open(_ mode: TextSearchMode<ModeNode>) async {
        mode.toggle()
        await mode.scanTask?.value
        await mode.recognizeTask?.value
    }

    private func type(_ text: String) {
        input.type(text, keyCode: 0)
    }

    private func presentation(_ query: String, _ status: SearchPresentation.Status, _ matches: [CGRect]) -> SearchPresentation {
        SearchPresentation(query: query, status: status, matches: matches, windowFrame: Self.window)
    }

    // MARK: Opening

    @Test func recognitionRunsAlongsideCollectionAfterTheBoxIsShown() async {
        let collecting = Gate()
        let recognizing = Gate()
        let mode = makeMode(
            collect: { _ in
                await collecting.pass()
                return Self.axRuns
            },
            recognize: { _, _ in
                await recognizing.pass()
                return Self.screenRuns
            }
        )
        mode.toggle()
        // Both are in flight at the same time, and the box is already up.
        await collecting.reached()
        await recognizing.reached()
        #expect(overlay.presentations == [presentation("", .collecting, [])])
        #expect(recognitions.calls.withLock { $0 } == ["recognize 42 \(Self.window)"])

        collecting.open()
        recognizing.open()
        await mode.scanTask?.value
        await mode.recognizeTask?.value
        #expect(overlay.last == presentation("", .idle, []))
    }

    @Test func turnedOffItNeverRecognizes() async {
        let mode = makeMode(enabled: false)
        await open(mode)
        type("status")
        #expect(recognitions.calls.withLock { $0 }.isEmpty)
        #expect(overlay.last == presentation("status", .noMatches, []))
    }

    // MARK: Choosing the source

    @Test func accessibilityMatchesWinWhenThereAreAny() async {
        let mode = makeMode()
        await open(mode)
        type("save")
        #expect(overlay.last == presentation("save", .matches(selected: 0), [Self.axRuns[0].frame]))
    }

    @Test func recognizedTextIsUsedWhenAccessibilityHasNoMatch() async {
        let mode = makeMode()
        await open(mode)
        type("STATUS")
        // Word boxes, in reading order.
        #expect(overlay.last == presentation("STATUS", .matches(selected: 0), [
            CGRect(x: 60, y: 300, width: 60, height: 16), CGRect(x: 110, y: 400, width: 60, height: 16),
        ]))
    }

    @Test func eachQueryChoosesItsSourceAgain() async {
        let mode = makeMode()
        await open(mode)
        type("s")
        // "s" is in "save" (Accessibility): only that source shows.
        #expect(overlay.last?.matches == [Self.axRuns[0].frame])
        type("t")
        // Only on screen; each match takes its word's box.
        #expect(overlay.last?.matches == [CGRect(x: 60, y: 300, width: 60, height: 16),
                                         CGRect(x: 110, y: 400, width: 60, height: 16)])
        input.press(keyCode: 51)
        #expect(overlay.last?.matches == [Self.axRuns[0].frame])
    }

    @Test func slowerRecognitionStillUpdatesTheCurrentQuery() async {
        let recognizing = Gate()
        let mode = makeMode(recognize: { _, _ in
            await recognizing.pass()
            return Self.screenRuns
        })
        mode.toggle()
        await mode.scanTask?.value
        await recognizing.reached()
        type("stat")
        // Accessibility is done without a match; OCR may still find one.
        #expect(overlay.last == presentation("stat", .collecting, []))
        type("u")

        recognizing.open()
        await mode.recognizeTask?.value
        #expect(overlay.last == presentation("statu", .matches(selected: 0), [
            CGRect(x: 60, y: 300, width: 60, height: 16), CGRect(x: 110, y: 400, width: 60, height: 16),
        ]))
    }

    @Test func aFailedRecognitionLeavesAccessibilityOnly() async {
        struct NoCapture: Error {}
        let mode = makeMode(recognize: { _, _ in throw NoCapture() })
        await open(mode)
        type("status")
        #expect(overlay.last == presentation("status", .noMatches, []))
    }

    @Test func staleRecognitionIsDroppedAfterDismissing() async {
        let recognizing = Gate()
        let calls = CallLog()
        let mode = makeMode(recognize: { _, _ in
            let call = calls.calls.withLock { $0.append("recognize"); return $0.count }
            guard call == 1 else { return [Self.line("fresh", y: 100)] }
            await recognizing.pass()
            return [Self.line("stale", y: 100)]
        })
        mode.toggle()
        await mode.scanTask?.value
        await recognizing.reached()
        let staleRecognition = mode.recognizeTask
        mode.toggle()
        #expect(!overlay.isVisible)
        let shown = overlay.presentations.count

        // Late results of the closed search show nothing.
        recognizing.open()
        await staleRecognition?.value
        #expect(overlay.presentations.count == shown)
        #expect(!overlay.isVisible)

        await open(mode)
        type("stale")
        #expect(overlay.last == presentation("stale", .noMatches, []))
    }

    // MARK: Navigating and jumping

    @Test func tabMovesThroughRecognizedMatches() async {
        let mode = makeMode()
        await open(mode)
        type("status")
        input.type("\t", keyCode: 48)
        #expect(overlay.last?.status == .matches(selected: 1))
        input.type("\t", keyCode: 48)
        #expect(overlay.last?.status == .matches(selected: 0))
    }

    @Test(arguments: [
        ("none", "press"), ("shift", "rightClick"), ("command", "doubleClick"), ("option", "moveCursor"),
    ])
    func returnJumpsToTheRecognizedMatch(modifier: String, action: String) async {
        let mode = makeMode()
        await open(mode)
        type("status")
        input.type("\t", keyCode: 48)
        input.type("\r", keyCode: 36, shift: modifier == "shift", command: modifier == "command",
                   option: modifier == "option")
        #expect(!mode.isActive)
        #expect(!overlay.isVisible)
        await mode.actionTask?.value
        #expect(screenJumps.calls.withLock { $0 } == ["\(action) save the status 9+6 at 110,400 60x16"])
        #expect(jumps.entries.withLock { $0 }.isEmpty)
    }

    @Test func returnBeforeRecognitionFinishesJumpsOnceItDoes() async {
        let recognizing = Gate()
        let mode = makeMode(recognize: { _, _ in
            await recognizing.pass()
            return Self.screenRuns
        })
        mode.toggle()
        await mode.scanTask?.value
        await recognizing.reached()
        // Accessibility is done without a match; only OCR can answer.
        type("status")
        input.type("\r", keyCode: 36, shift: true)
        #expect(mode.isActive)

        recognizing.open()
        await mode.recognizeTask?.value
        await mode.actionTask?.value
        #expect(!mode.isActive)
        #expect(screenJumps.calls.withLock { $0 } == ["rightClick git status 4+6 at 60,300 60x16"])
    }

    @Test func returnDuringBothCollectionsWaitsForRecognition() async {
        let collecting = Gate()
        let recognizing = Gate()
        let mode = makeMode(
            collect: { _ in
                await collecting.pass()
                return Self.axRuns
            },
            recognize: { _, _ in
                await recognizing.pass()
                return Self.screenRuns
            }
        )
        mode.toggle()
        await collecting.reached()
        await recognizing.reached()
        type("status")
        input.type("\r", keyCode: 36)

        // Accessibility finishes first without a match: the jump must wait.
        collecting.open()
        await mode.scanTask?.value
        #expect(mode.isActive)
        #expect(overlay.last == presentation("status", .collecting, []))

        recognizing.open()
        await mode.recognizeTask?.value
        await mode.actionTask?.value
        #expect(screenJumps.calls.withLock { $0 } == ["press git status 4+6 at 60,300 60x16"])
    }

    // MARK: Accessibility only

    /// One session: open, type, navigate, jump.
    private func script(_ mode: TextSearchMode<ModeNode>) async -> (presentations: [SearchPresentation], jumps: [String]) {
        await open(mode)
        type("sa")
        type("x")
        input.press(keyCode: 51)
        input.type("\t", keyCode: 48)
        input.type("\r", keyCode: 36, command: true)
        await mode.actionTask?.value
        return (overlay.presentations, jumps.entries.withLock { $0 })
    }

    @Test func turnedOffItBehavesExactlyLikeAccessibilityOnly() async {
        let withoutSource = TextSearchModeScreenTextTests()
        let accessibilityOnly = await withoutSource.script(withoutSource.makeMode(source: false))
        let turnedOff = await script(makeMode(enabled: false))
        #expect(turnedOff.presentations == accessibilityOnly.presentations)
        #expect(turnedOff.jumps == accessibilityOnly.jumps)
        #expect(turnedOff.jumps == ["doubleClick save 0+2 at 10,10 100x20"])
        #expect(recognitions.calls.withLock { $0 }.isEmpty)
    }
}
