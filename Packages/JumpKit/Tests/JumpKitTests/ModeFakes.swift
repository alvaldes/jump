import CoreGraphics
@testable import JumpKit

// Recording fakes for the modes' system boundaries.

final class FakeOverlay: OverlayPresenting {
    var isVisible = false
    var canTakeKeyboard = true
    private(set) var shownHints: [[HintPresentation]] = []
    private(set) var outlines: [CGRect] = []
    private(set) var filters: [String] = []
    private(set) var rotations = 0
    private(set) var hideCount = 0

    func show(_ hints: [HintPresentation], focusPoint: CGPoint?) {
        shownHints.append(hints)
        isVisible = true
    }

    func showOutline(_ frame: CGRect) -> Bool {
        outlines.append(frame)
        isVisible = true
        return canTakeKeyboard
    }

    func filter(typed: String) { filters.append(typed) }
    func rotate() { rotations += 1 }

    func hide() {
        hideCount += 1
        isVisible = false
    }
}

/// Lets tests type keys and send app events to the active mode.
final class FakeInput: ModeInputSource {
    private var handler: ModeInputHandler?
    /// The app whose focus the mode asked to watch.
    private(set) var target: FrontmostApp?
    var isListening: Bool { handler != nil }

    func start(_ handler: ModeInputHandler, target: FrontmostApp) {
        self.handler = handler
        self.target = target
    }

    func stop() { handler = nil }

    func type(_ characters: String, keyCode: UInt16 = 0, shift: Bool = false, command: Bool = false,
              option: Bool = false, isRepeat: Bool = false) {
        for character in characters {
            handler?.keyDown(KeyPress(keyCode: keyCode, characters: String(character), shift: shift,
                                      command: command, option: option, isRepeat: isRepeat))
        }
    }

    func press(keyCode: UInt16, characters: String = "") {
        handler?.keyDown(KeyPress(keyCode: keyCode, characters: characters))
    }

    func release(keyCode: UInt16) { handler?.keyUp(keyCode) }
    func moveFocusAway() { handler?.focusLeft() }
    func loseKeyboard() { handler?.keyboardLost() }
}

final class FakePointer: PointerControlling {
    var location = CGPoint(x: 5, y: 5)
    private(set) var moves: [CGPoint] = []

    func move(to point: CGPoint) {
        moves.append(point)
        location = point
    }
}

let fakeApp = FrontmostApp(pid: 42, name: "Target", bundleIdentifier: "com.example.target")

nonisolated struct FakeControl: ScrollControlling {
    let id: Int
    func scroll(_ direction: ScrollDirection, pixels: CGFloat) -> ScrollOutcome { .scrolled }
    func scrollToEdge(top: Bool) -> ScrollOutcome { .scrolled }
}

/// Records what scroll mode asks for, as readable strings.
final class FakeDriver: ScrollDriving {
    var onAccessibilityFailure: ((FakeControl) -> Void)?
    private(set) var calls: [String] = []

    func startSmooth(_ direction: ScrollDirection, via output: ScrollOutput<FakeControl>) {
        calls.append("smooth \(direction) \(describe(output))")
    }

    func startHalfPage(_ direction: ScrollDirection, in area: CGRect, via output: ScrollOutput<FakeControl>) {
        calls.append("halfPage \(direction) \(describe(output))")
    }

    func scrollToEdge(top: Bool, via output: ScrollOutput<FakeControl>) {
        calls.append("\(top ? "top" : "bottom") \(describe(output))")
    }

    func stop() { calls.append("stop") }

    /// Calls other than `stop`, which is issued defensively in many places.
    var commands: [String] { calls.filter { $0 != "stop" } }

    private func describe(_ output: ScrollOutput<FakeControl>) -> String {
        switch output {
        case .accessibility(let control): "ax\(control.id)"
        case .wheel: "wheel"
        }
    }
}
