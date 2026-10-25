import AppKit
import Testing
@testable import JumpKit

/// The overlay as `AppKitModeInput` sees it: which object is its panel and
/// whether one of its panels has the keyboard.
final class FakeOverlayKeyboard: OverlayKeyboard {
    let panel = NSObject()
    var hasKeyPanel = false
    func isOverlayWindow(_ object: Any?) -> Bool { (object as AnyObject?) === panel }
}

/// Records which app's window focus is watched and lets tests move it.
final class FakeWindowFocus: WindowFocusObserving {
    private(set) var watchedPids: [pid_t] = []
    private(set) var stopCount = 0
    /// The latest callback, kept after `stop` to replay stale reports.
    private(set) var onFocusLeft: (() -> Void)?
    private(set) var isWatching = false

    func start(pid: pid_t, onFocusLeft: @escaping () -> Void) {
        watchedPids.append(pid)
        self.onFocusLeft = onFocusLeft
        isWatching = true
    }

    func stop() {
        stopCount += 1
        isWatching = false
    }

    func moveFocus() { onFocusLeft?() }
}

/// Stands in for `NSEvent`'s local monitor.
final class FakeKeyMonitor {
    private(set) var handler: ((NSEvent) -> NSEvent?)?
    private(set) var removed = 0

    var monitor: KeyEventMonitor {
        KeyEventMonitor(
            add: { [unowned self] handler in
                self.handler = handler
                return "token"
            },
            remove: { [unowned self] _ in
                self.handler = nil
                self.removed += 1
            }
        )
    }

    /// Returns what the monitor hands back to AppKit (`nil` swallows the key).
    func send(
        _ type: NSEvent.EventType, keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
        return handler?(event)
    }
}

/// What a mode was told.
final class InputEvents {
    var log: [String] = []

    var handler: ModeInputHandler {
        ModeInputHandler(
            keyDown: { [unowned self] in self.log.append("down \($0.characters)") },
            keyUp: { [unowned self] in self.log.append("up \($0)") },
            focusLeft: { [unowned self] in self.log.append("focus left") },
            keyboardLost: { [unowned self] in self.log.append("keyboard lost") }
        )
    }
}

@Suite("AppKitModeInput")
struct AppKitModeInputTests {
    let overlay = FakeOverlayKeyboard()
    let focus = FakeWindowFocus()
    let keys = FakeKeyMonitor()
    let workspace = NotificationCenter()
    let windows = NotificationCenter()
    let events = InputEvents()

    private func makeInput() -> AppKitModeInput {
        AppKitModeInput(overlay: overlay, windowFocus: focus, keyMonitor: keys.monitor,
                        workspaceCenter: workspace, windowCenter: windows)
    }

    /// Lets the deferred key-loss check run.
    private func nextMainTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func activateOtherApp() {
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    private func resignOverlayKey() {
        windows.post(name: NSWindow.didResignKeyNotification, object: overlay.panel)
    }

    // MARK: Keys

    @Test func deliversAndSwallowsKeys() {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        #expect(keys.send(.keyDown, keyCode: 0, characters: "a") == nil)
        #expect(keys.send(.keyUp, keyCode: 0, characters: "a") == nil)
        #expect(events.log == ["down a", "up 0"])
    }

    @Test func commandBacktickLeavesInsteadOfReachingTheMode() {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        #expect(keys.send(.keyDown, keyCode: 50, characters: "`", modifiers: .command) == nil)
        #expect(events.log == ["focus left"])
    }

    @Test func backtickWithoutCommandStillReachesTheMode() {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        #expect(keys.send(.keyDown, keyCode: 50, characters: "`") == nil)
        #expect(events.log == ["down `"])
    }

    // MARK: Focus leaving the target window

    @Test func watchesTheTargetAppsWindowFocus() {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        #expect(focus.watchedPids == [fakeApp.pid])
        #expect(focus.isWatching)
    }

    @Test func focusMovingToAnotherWindowOfTheTargetAppIsReported() {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        focus.moveFocus()
        #expect(events.log == ["focus left"])
    }

    @Test func anotherAppComingToTheFrontIsReported() {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        activateOtherApp()
        #expect(events.log == ["focus left"])
    }

    @Test func aFocusReportFromAnEarlierSessionIsIgnored() {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        let stale = focus.onFocusLeft
        input.stop()
        input.start(events.handler, target: fakeApp)
        stale?()
        #expect(events.log.isEmpty)
    }

    // MARK: Overlay key loss

    @Test func overlayLosingTheKeyboardIsReportedAfterThisTurn() async {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        resignOverlayKey()
        #expect(events.log.isEmpty)
        await nextMainTurn()
        #expect(events.log == ["keyboard lost"])
    }

    @Test func keyboardMovingToAnotherOverlayPanelIsNotALoss() async {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        overlay.hasKeyPanel = true
        resignOverlayKey()
        await nextMainTurn()
        #expect(events.log.isEmpty)
    }

    @Test func otherWindowsResigningKeyAreIgnored() async {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        windows.post(name: NSWindow.didResignKeyNotification, object: NSObject())
        await nextMainTurn()
        #expect(events.log.isEmpty)
    }

    @Test func aKeyLossCheckFromAnEarlierSessionIsIgnored() async {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        resignOverlayKey()
        input.stop()
        input.start(events.handler, target: fakeApp)
        await nextMainTurn()
        #expect(events.log.isEmpty)
    }

    // MARK: Stopping

    @Test func stopTearsEverythingDown() async {
        let input = makeInput()
        input.start(events.handler, target: fakeApp)
        input.stop()
        #expect(!focus.isWatching)
        #expect(keys.removed == 1)
        #expect(keys.handler == nil)
        activateOtherApp()
        resignOverlayKey()
        await nextMainTurn()
        #expect(events.log.isEmpty)
    }
}

@Suite("Window focus change")
struct WindowFocusChangeTests {
    @Test func anotherWindowTakingFocusLeavesTheTarget() {
        #expect(WindowFocusChange.leftTarget(initial: "editor", current: "terminal"))
    }

    @Test func theSameWindowKeepsTheTarget() {
        #expect(!WindowFocusChange.leftTarget(initial: "editor", current: "editor"))
    }

    /// The overlay taking the keyboard can leave the app with no focused window
    /// for a moment; that is not the user moving focus.
    @Test func noFocusedWindowKeepsTheTarget() {
        #expect(!WindowFocusChange.leftTarget(initial: "editor", current: String?.none))
        #expect(!WindowFocusChange.leftTarget(initial: String?.none, current: "terminal"))
    }

    // Changes while the observer registers (before any notification can arrive).

    @Test func aWindowSwitchDuringRegistrationLeavesTheTarget() {
        #expect(WindowFocusChange.leftDuringRegistration(initial: "editor", current: "terminal", appHidden: false))
    }

    @Test func hidingTheAppDuringRegistrationLeavesTheTarget() {
        #expect(WindowFocusChange.leftDuringRegistration(initial: "editor", current: "editor", appHidden: true))
    }

    @Test func nothingChangingDuringRegistrationKeepsTheTarget() {
        #expect(!WindowFocusChange.leftDuringRegistration(initial: "editor", current: "editor", appHidden: false))
        #expect(!WindowFocusChange.leftDuringRegistration(initial: "editor", current: String?.none, appHidden: false))
    }
}
