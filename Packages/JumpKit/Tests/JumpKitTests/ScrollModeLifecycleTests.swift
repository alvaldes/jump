import CoreGraphics
import Testing
@testable import JumpKit

@Suite("ScrollMode lifecycle")
struct ScrollModeLifecycleTests {
    let overlay = FakeOverlay()
    let input = FakeInput()
    let pointer = FakePointer()
    let driver = FakeDriver()

    static let mainArea = CGRect(x: 0, y: 0, width: 400, height: 600)
    static let sideArea = CGRect(x: 400, y: 0, width: 200, height: 600)

    private func makeMode(
        targets: [ScrollTarget<FakeControl>] = [
            ScrollTarget(frame: mainArea, control: FakeControl(id: 1)),
            ScrollTarget(frame: sideArea, control: nil),
        ],
        trusted: Bool = true,
        frontmost: @escaping () -> FrontmostApp? = { fakeApp }
    ) -> ScrollMode<FakeDriver> {
        ScrollMode(
            overlay: overlay, pointer: pointer, input: input, driver: driver,
            isTrusted: { trusted }, frontmostApp: frontmost, screens: { [] },
            findTargets: { _, _ in targets }, sequenceDelay: .seconds(5)
        )
    }

    private func enter(_ mode: ScrollMode<FakeDriver>) async {
        mode.toggle()
        await mode.scanTask?.value
    }

    // MARK: Entering and leaving

    @Test func entersOnTheLargestAreaAndListens() async {
        let mode = makeMode()
        await enter(mode)
        #expect(mode.isActive)
        #expect(overlay.outlines == [Self.mainArea])
        #expect(input.isListening)
    }

    @Test func doesNothingWithoutAccessibilityAccess() async {
        let mode = makeMode(trusted: false)
        await enter(mode)
        #expect(!mode.isActive)
        #expect(overlay.outlines.isEmpty)
    }

    @Test func doesNothingWithoutScrollAreas() async {
        let mode = makeMode(targets: [])
        await enter(mode)
        #expect(!mode.isActive)
        #expect(!input.isListening)
    }

    @Test func doesNotEnterWhenTheAppChangedDuringTheSearch() async {
        var front: FrontmostApp? = fakeApp
        let mode = makeMode(frontmost: { front })
        mode.toggle()
        front = FrontmostApp(pid: 7, name: "Other", bundleIdentifier: nil)
        await mode.scanTask?.value
        #expect(!mode.isActive)
        #expect(overlay.outlines.isEmpty)
    }

    @Test func leavesWhenTheOverlayCannotTakeTheKeyboard() async {
        overlay.canTakeKeyboard = false
        let mode = makeMode()
        await enter(mode)
        #expect(!mode.isActive)
        #expect(!input.isListening)
    }

    @Test(arguments: ["escape", "hotkey", "app switch", "keyboard lost"])
    func everyExitLeavesTheModeAndStopsListening(exit: String) async {
        let mode = makeMode()
        await enter(mode)
        switch exit {
        case "escape": input.press(keyCode: 53)
        case "hotkey": mode.toggle()
        case "app switch": input.switchApp()
        default: input.loseKeyboard()
        }
        #expect(!mode.isActive)
        #expect(!input.isListening)
        #expect(!overlay.isVisible)
    }

    @Test func hotkeyDuringTheSearchCancelsIt() async {
        let mode = makeMode()
        mode.toggle()
        // Keep the search: the second press clears the mode's reference to it.
        let search = mode.scanTask
        mode.toggle()
        await search?.value
        #expect(!mode.isActive)
        #expect(overlay.outlines.isEmpty)
    }

    // MARK: Pointer

    @Test func accessibilityAreasLeaveThePointerAlone() async {
        let mode = makeMode()
        await enter(mode)
        mode.deactivate()
        #expect(pointer.moves.isEmpty)
    }

    @Test func wheelAreasMoveThePointerAndRestoreItOnExit() async {
        let mode = makeMode(targets: [ScrollTarget(frame: Self.sideArea, control: nil)])
        await enter(mode)
        #expect(pointer.moves == [CGPoint(x: 500, y: 300)])
        mode.deactivate()
        #expect(pointer.moves.last == CGPoint(x: 5, y: 5))
    }

    // MARK: Keys

    @Test func heldKeysScrollUntilTheirOwnRelease() async {
        let mode = makeMode()
        await enter(mode)
        input.type("j", keyCode: 38)
        input.release(keyCode: 40)  // another key: keeps scrolling
        #expect(driver.calls.last == "smooth down ax1")
        input.release(keyCode: 38)
        #expect(driver.calls.last == "stop")
    }

    @Test func autoRepeatDoesNotRestartTheScroll() async {
        let mode = makeMode()
        await enter(mode)
        input.type("j", keyCode: 38)
        input.type("j", keyCode: 38, isRepeat: true)
        #expect(driver.commands == ["smooth down ax1"])
    }

    @Test func shortcutsAreNotScrollCommands() async {
        let mode = makeMode()
        await enter(mode)
        input.type("j", command: true)
        input.type("d", option: true)
        #expect(driver.commands.isEmpty)
    }

    @Test func halfPagesAndEdges() async {
        let mode = makeMode()
        await enter(mode)
        input.type("d")
        input.type("u")
        input.type("G", shift: true)
        input.type("gg")
        #expect(driver.commands == ["halfPage down ax1", "halfPage up ax1", "bottom ax1", "top ax1"])
    }

    @Test func tabMovesToTheNextAreaAndWraps() async {
        let mode = makeMode()
        await enter(mode)
        input.press(keyCode: 48)
        input.type("j")
        input.press(keyCode: 48)
        #expect(overlay.outlines == [Self.mainArea, Self.sideArea, Self.mainArea])
        #expect(driver.commands == ["smooth down wheel"])
    }

    // MARK: Accessibility failure

    @Test func aFailureSwitchesToTheWheelAndResumesAHeldScroll() async {
        let mode = makeMode()
        await enter(mode)
        input.type("j", keyCode: 38)
        driver.onAccessibilityFailure?(FakeControl(id: 1))
        #expect(driver.commands == ["smooth down ax1", "smooth down wheel"])
        #expect(pointer.moves == [CGPoint(x: 200, y: 300)])
    }

    @Test func aFailureOfAnotherAreaIsIgnored() async {
        let mode = makeMode()
        await enter(mode)
        driver.onAccessibilityFailure?(FakeControl(id: 99))
        input.type("j")
        #expect(driver.commands == ["smooth down ax1"])
        #expect(pointer.moves.isEmpty)
    }
}
