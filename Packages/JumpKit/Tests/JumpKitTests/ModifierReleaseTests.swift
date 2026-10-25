import CoreGraphics
import Synchronization
import Testing
@testable import JumpKit

@Suite("Modifier release")
struct ModifierReleaseTests {
    /// Flag readings in order; the last one repeats.
    nonisolated final class Readings: Sendable {
        private let values: Mutex<[CGEventFlags]>
        private let count = Mutex(0)

        init(_ values: [CGEventFlags]) { self.values = Mutex(values) }

        func next() -> CGEventFlags {
            count.withLock { $0 += 1 }
            return values.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] }
        }

        var reads: Int { count.withLock { $0 } }
    }

    @Test func actionModifiersCountAsHeld() {
        for flag in [CGEventFlags.maskCommand, .maskShift, .maskAlternate, .maskControl] {
            #expect(ModifierRelease.holdsModifiers(flag))
        }
        // Caps Lock and the numeric pad flag are not keys the user holds for an action.
        #expect(!ModifierRelease.holdsModifiers([.maskAlphaShift, .maskNumericPad]))
        #expect(!ModifierRelease.holdsModifiers([]))
    }

    @Test func returnsAsSoonAsTheModifiersAreReleased() async {
        let readings = Readings([.maskCommand, .maskCommand, []])
        let released = await ModifierRelease.wait(timeout: .seconds(1), poll: .milliseconds(10),
                                                  readFlags: readings.next, sleep: { _ in })
        #expect(released)
        #expect(readings.reads == 3)
    }

    @Test func doesNotWaitWhenNothingIsHeld() async {
        let readings = Readings([[]])
        #expect(await ModifierRelease.wait(timeout: .seconds(1), poll: .milliseconds(10),
                                           readFlags: readings.next, sleep: { _ in }))
        #expect(readings.reads == 1)
    }

    /// A modifier held for good (or a stuck key) must not block the action forever.
    @Test func givesUpAfterTheTimeout() async {
        let readings = Readings([.maskCommand])
        let released = await ModifierRelease.wait(timeout: .milliseconds(100), poll: .milliseconds(10),
                                                  readFlags: readings.next, sleep: { _ in })
        #expect(!released)
        #expect(readings.reads == 11)
    }

    /// A zero interval must not divide by zero; it checks once.
    @Test func aZeroPollChecksOnce() async {
        let readings = Readings([.maskCommand])
        let released = await ModifierRelease.wait(timeout: .seconds(1), poll: .zero,
                                                  readFlags: readings.next, sleep: { _ in })
        #expect(!released)
        #expect(readings.reads == 1)
    }
}

@Suite("Synthesized clicks wait for modifiers")
struct ClickWaitTests {
    nonisolated final class Steps: Sendable {
        let log = Mutex<[String]>([])
        func add(_ step: String) { log.withLock { $0.append(step) } }
        var all: [String] { log.withLock { $0 } }
    }

    @Test(arguments: [
        (HintAction.press, "post left 1"), (.rightClick, "post right 1"), (.doubleClick, "post left 2"),
    ])
    func everyClickWaitsBeforePosting(action: HintAction, posted: String) async {
        let steps = Steps()
        await ElementActions.click(action, at: CGPoint(x: 5, y: 7),
                                   waitForRelease: { steps.add("wait") },
                                   post: { _, button, count in steps.add("post \(button == .right ? "right" : "left") \(count)") },
                                   movePointer: { _ in steps.add("move") })
        #expect(steps.all == ["wait", posted])
    }

    /// Moving the pointer is not a click: it never waits.
    @Test func movingThePointerDoesNotWait() async {
        let steps = Steps()
        await ElementActions.click(.moveCursor, at: CGPoint(x: 5, y: 7),
                                   waitForRelease: { steps.add("wait") },
                                   post: { _, _, _ in steps.add("post") },
                                   movePointer: { _ in steps.add("move") })
        #expect(steps.all == ["move"])
    }
}
