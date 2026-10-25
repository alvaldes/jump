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
        scan: @escaping HintMode<ModeNode>.Scanner = { _ in
            ScanResult(elements: elements, visitedCount: 3, isTruncated: false)
        }
    ) -> HintMode<ModeNode> {
        let actions = self.actions
        return HintMode(
            overlay: overlay, input: input, isTrusted: { trusted }, hintCharacters: { "sa" },
            frontmostApp: { frontmost }, scan: scan,
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
        mode.toggle()
        await mode.scanTask?.value
        #expect(overlay.shownHints.isEmpty)
        #expect(!mode.isShowingHints)
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

    @Test func spaceRotatesOverlappingHints() async {
        let mode = makeMode()
        await show(mode)
        input.press(keyCode: 49, characters: " ")
        #expect(overlay.rotations == 1)
        #expect(mode.isShowingHints)
    }

    // MARK: Dismissing

    @Test(arguments: ["escape", "typo", "hotkey", "app switch", "keyboard lost"])
    func everyExitHidesHintsWithoutActing(exit: String) async {
        let mode = makeMode()
        await show(mode)
        switch exit {
        case "escape": input.press(keyCode: 53)
        case "typo": input.type("x")
        case "hotkey": mode.toggle()
        case "app switch": input.switchApp()
        default: input.loseKeyboard()
        }
        #expect(!mode.isShowingHints)
        #expect(!input.isListening)
        #expect(!overlay.isVisible)
        #expect(await performed(mode).isEmpty)
    }
}
