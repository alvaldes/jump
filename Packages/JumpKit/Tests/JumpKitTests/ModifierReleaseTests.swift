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
}
