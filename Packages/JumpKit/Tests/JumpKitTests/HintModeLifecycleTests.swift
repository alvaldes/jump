import CoreGraphics
import Synchronization
import Testing
@testable import JumpKit

nonisolated struct ModeNode: AccessibilityNode {
    let id: String
    func attributes(prefetchingChildren: Bool) -> NodeAttributes? { nil }
    func actions() -> [String] { [] }
    func children(role: String) -> [ModeNode] { [] }
}

/// Records the actions hint mode performs.
final class ActionLog: Sendable {
    let entries = Mutex<[String]>([])
    func record(_ action: HintAction, _ element: ScannedElement<ModeNode>) {
        entries.withLock { $0.append("\(action) \(element.node.id)") }
    }
}

/// Records calls made from the mode's async boundaries.
final class CallLog: Sendable {
    let calls = Mutex<[String]>([])
}

@Suite("HintMode lifecycle")
struct HintModeLifecycleTests {
    let overlay = FakeOverlay()
    let input = FakeInput()
    let actions = ActionLog()

    /// Two elements in reading order: with characters "sa" they get labels A and S
    /// (labels are sorted, see HintLabels).
    private static let elements = [
        ScannedElement(node: ModeNode(id: "save"), role: "AXButton", frame: CGRect(x: 10, y: 10, width: 40, height: 20)),
        ScannedElement(node: ModeNode(id: "cancel"), role: "AXButton", frame: CGRect(x: 100, y: 10, width: 40, height: 20)),
    ]

    private func makeMode(
        trusted: Bool = true,
        frontmost: FrontmostApp? = fakeApp,
        prepareApp: @escaping (FrontmostApp) async -> Void = { _ in },
        scan: @escaping HintMode<ModeNode>.Scanner = { _ in
            ScanResult(elements: elements, visitedCount: 3, isTruncated: false)
        },
        actionModifiers: ActionModifiers = .standard
    ) -> HintMode<ModeNode> {
        let actions = self.actions
        return HintMode(
            overlay: overlay, input: input, isTrusted: { trusted }, hintCharacters: { "sa" },
            actionModifiers: { actionModifiers },
            frontmostApp: { frontmost }, prepareApp: prepareApp, scan: scan,
            perform: { action, element in actions.record(action, element) }
        )
    }

    private func show(_ mode: HintMode<ModeNode>) async {
        mode.toggle()
        await mode.scanTask?.value
    }

    private func performed(_ mode: HintMode<ModeNode>) async -> [String] {
        await mode.actionTask?.value
        return actions.entries.withLock { $0 }
    }

    // MARK: Showing hints

    @Test func showsOneHintPerElementAndListens() async {
        let mode = makeMode()
        await show(mode)
        #expect(overlay.shownHints.first?.map(\.label) == ["A", "S"])
        #expect(mode.isShowingHints)
        #expect(input.isListening)
        #expect(mode.lastSummary?.hasPrefix("Target: 2 hints") == true)
    }

    @Test func explainsWhenAccessibilityAccessIsMissing() async {
        let mode = makeMode(trusted: false)
        await show(mode)
        #expect(mode.lastSummary == "Accessibility access required")
        #expect(overlay.shownHints.isEmpty)
    }

    @Test func doesNotScanJUMPItself() async {
        let mode = makeMode(frontmost: nil)
        await show(mode)
        #expect(mode.lastSummary == "No app to scan")
        #expect(overlay.shownHints.isEmpty)
    }

    @Test func reportsAWindowlessApp() async {
        struct NoWindow: Error {}
        let mode = makeMode(scan: { _ in throw NoWindow() })
        await show(mode)
        #expect(mode.lastSummary == "Target: no focused window")
        #expect(!input.isListening)
    }

    @Test func hotkeyDuringTheScanShowsNothing() async {
        let mode = makeMode()
        mode.toggle()
        // Keep the scan: the second press clears the mode's reference to it.
        let scan = mode.scanTask
        mode.toggle()
        await scan?.value
        #expect(overlay.shownHints.isEmpty)
        #expect(!mode.isShowingHints)
    }

    @Test func preparesTheAppBeforeScanningIt() async {
        // Chromium and Electron build their tree only once asked, so preparation must come first.
        let log = CallLog()
        let mode = makeMode(
            prepareApp: { app in log.calls.withLock { $0.append("prepare \(app.pid) \(app.bundleIdentifier ?? "")") } },
            scan: { app in
                log.calls.withLock { $0.append("scan \(app.pid)") }
                return ScanResult(elements: Self.elements, visitedCount: 3, isTruncated: false)
            }
        )
        await show(mode)
        #expect(log.calls.withLock { $0 } == ["prepare 42 com.example.target", "scan 42"])
        #expect(mode.isShowingHints)
    }

    @Test(arguments: [false, true])
    func aScanWithNoElementsShowsNothingAndEndsTheMode(truncated: Bool) async {
        let mode = makeMode(scan: { _ in ScanResult(elements: [], visitedCount: 5, isTruncated: truncated) })
        await show(mode)
        #expect(overlay.shownHints.isEmpty)
        #expect(!overlay.isVisible)
        #expect(overlay.hideCount == 0)
        #expect(!mode.isShowingHints)
        #expect(!input.isListening)
        #expect(mode.scanTask == nil)
        let summary = mode.lastSummary ?? ""
        #expect(summary.hasPrefix("Target: 0 hints in "))
        #expect(summary.hasSuffix(truncated ? " ms (truncated)" : " ms"))
    }

    @Test func theHotkeyAfterAnEmptyScanScansAgain() async {
        let scans = CallLog()
        let mode = makeMode(scan: { _ in
            scans.calls.withLock { $0.append("scan") }
            return ScanResult(elements: [], visitedCount: 1, isTruncated: false)
        })
        await show(mode)
        await show(mode)
        #expect(scans.calls.withLock { $0 } == ["scan", "scan"])
        #expect(overlay.shownHints.isEmpty)
        #expect(await performed(mode).isEmpty)
    }

    // MARK: Selecting

    @Test func typingALabelPressesItsElement() async {
        let mode = makeMode()
        await show(mode)
        input.type("s")
        #expect(await performed(mode) == ["press cancel"])
        #expect(!mode.isShowingHints)
        #expect(!input.isListening)
    }

    @Test(arguments: [
        ("shift", "rightClick save"), ("command", "doubleClick save"), ("option", "moveCursor save"),
    ])
    func modifiersChooseTheAction(modifier: String, expected: String) async {
        let mode = makeMode()
        await show(mode)
        input.type("a", shift: modifier == "shift", command: modifier == "command", option: modifier == "option")
        #expect(await performed(mode) == [expected])
    }

    @Test func aCustomModifierChoosesTheAction() async {
        var modifiers = ActionModifiers.standard
        modifiers.assign(.control, to: .doubleClick)
        let mode = makeMode(actionModifiers: modifiers)
        await show(mode)
        input.type("a", control: true)
        #expect(await performed(mode) == ["doubleClick save"])
    }

    @Test func spaceRotatesOverlappingHints() async {
        let mode = makeMode()
        await show(mode)
        input.press(keyCode: 49, characters: " ")
        #expect(overlay.rotations == 1)
        #expect(mode.isShowingHints)
    }

    // MARK: Dismissing

    @Test func watchesTheFocusOfTheAppItActsOn() async {
        let mode = makeMode()
        await show(mode)
        #expect(input.target == fakeApp)
    }

    @Test(arguments: ["escape", "typo", "hotkey", "focus left", "keyboard lost"])
    func everyExitHidesHintsWithoutActing(exit: String) async {
        let mode = makeMode()
        await show(mode)
        switch exit {
        case "escape": input.press(keyCode: 53)
        case "typo": input.type("x")
        case "hotkey": mode.toggle()
        case "focus left": input.moveFocusAway()
        default: input.loseKeyboard()
        }
        #expect(!mode.isShowingHints)
        #expect(!input.isListening)
        #expect(!overlay.isVisible)
        #expect(await performed(mode).isEmpty)
    }
}

@Suite("Mode switching")
struct ModeSwitcherTests {
    @Test func theTwoModesNeverRunTogether() async {
        let overlay = FakeOverlay()
        let hintInput = FakeInput()
        let scrollInput = FakeInput()
        let hints = HintMode<ModeNode>(
            overlay: overlay, input: hintInput, isTrusted: { true }, hintCharacters: { "sa" },
            frontmostApp: { fakeApp },
            scan: { _ in
                ScanResult(elements: [ScannedElement(node: ModeNode(id: "a"), role: "AXButton",
                                                     frame: CGRect(x: 0, y: 0, width: 10, height: 10))],
                           visitedCount: 1, isTruncated: false)
            },
            perform: { _, _ in }
        )
        let scroll = ScrollMode(
            overlay: overlay, pointer: FakePointer(), input: scrollInput, driver: FakeDriver(),
            isTrusted: { true }, frontmostApp: { fakeApp }, screens: { [] },
            findTargets: { _, _ in [ScrollTarget(frame: CGRect(x: 0, y: 0, width: 100, height: 100), control: FakeControl(id: 1))] }
        )
        let switcher = ModeSwitcher(hints: hints, scroll: scroll)

        switcher.activateScroll()
        await scroll.scanTask?.value
        #expect(scroll.isActive)

        switcher.activateHints()
        await hints.scanTask?.value
        #expect(!scroll.isActive)
        #expect(!scrollInput.isListening)
        #expect(hints.isShowingHints)

        switcher.activateScroll()
        await scroll.scanTask?.value
        #expect(!hints.isShowingHints)
        #expect(!hintInput.isListening)
        #expect(scroll.isActive)
    }

    @Test func textSearchNeverRunsWithHintsOrScroll() async {
        let overlay = FakeOverlay()
        let hintInput = FakeInput()
        let scrollInput = FakeInput()
        let searchInput = FakeInput()
        let searchOverlay = FakeSearchOverlay()
        let hints = HintMode<ModeNode>(
            overlay: overlay, input: hintInput, isTrusted: { true }, hintCharacters: { "sa" },
            frontmostApp: { fakeApp },
            scan: { _ in
                ScanResult(elements: [ScannedElement(node: ModeNode(id: "a"), role: "AXButton",
                                                     frame: CGRect(x: 0, y: 0, width: 10, height: 10))],
                           visitedCount: 1, isTruncated: false)
            },
            perform: { _, _ in }
        )
        let scroll = ScrollMode(
            overlay: overlay, pointer: FakePointer(), input: scrollInput, driver: FakeDriver(),
            isTrusted: { true }, frontmostApp: { fakeApp }, screens: { [] },
            findTargets: { _, _ in [ScrollTarget(frame: CGRect(x: 0, y: 0, width: 100, height: 100), control: FakeControl(id: 1))] }
        )
        let search = TextSearchMode<ModeNode>(
            overlay: searchOverlay, input: searchInput, isTrusted: { true }, frontmostApp: { fakeApp },
            windowFrame: { _ in CGRect(x: 0, y: 0, width: 800, height: 600) }, collect: { _ in [] },
            locate: { _ in nil }, perform: { _, _ in }
        )
        let switcher = ModeSwitcher(hints: hints, scroll: scroll, search: search)

        switcher.activateHints()
        await hints.scanTask?.value
        switcher.activateSearch()
        await search.scanTask?.value
        #expect(!hints.isShowingHints)
        #expect(!hintInput.isListening)
        #expect(search.isActive)

        switcher.activateScroll()
        await scroll.scanTask?.value
        #expect(!search.isActive)
        #expect(!searchInput.isListening)
        #expect(scroll.isActive)

        switcher.activateSearch()
        await search.scanTask?.value
        #expect(!scroll.isActive)
        #expect(!scrollInput.isListening)
        #expect(search.isActive)

        switcher.activateHints()
        await hints.scanTask?.value
        #expect(!search.isActive)
        #expect(hints.isShowingHints)

        // The search hotkey again closes the search, like the other two.
        switcher.activateSearch()
        await search.scanTask?.value
        switcher.activateSearch()
        #expect(!search.isActive)
    }
}
