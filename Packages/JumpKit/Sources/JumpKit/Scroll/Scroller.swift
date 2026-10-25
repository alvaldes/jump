import CoreGraphics
import Foundation
import Synchronization

public nonisolated struct ScrollDelta: Sendable, Equatable {
    public let horizontal: Int32
    public let vertical: Int32
}

/// How scroll commands reach the app.
public nonisolated enum ScrollOutput: Sendable {
    /// Writes the area's scroll bar values: independent of the pointer.
    case accessibility(AXScrollControl)
    /// Synthetic wheel events, delivered to whatever is under the pointer.
    case wheel
}

/// Turns scroll commands into continuous, half-page or edge scrolling
/// (port of Vimac's `ChunkyScroller`).
public final class Scroller {
    /// Pixels per tick while a direction key is held, at 60 ticks per second.
    static let smoothStep: Int32 = 16
    static let smoothInterval: TimeInterval = 1.0 / 60
    /// Half-page jumps repeat at this pace while the key is held.
    static let halfPageInterval: TimeInterval = 0.25
    /// Large enough to reach either end of any document in one event (Vimac).
    static let edgeDistance = Int32(Int16.max)

    private var timer: Timer?
    private let writer = AccessibilityWriter()

    public init() {}

    /// Scrolls continuously until `stop()`.
    public func startSmooth(_ direction: ScrollDirection, via output: ScrollOutput) {
        repeatStep(every: Self.smoothInterval, step(direction, distance: Self.smoothStep, via: output))
    }

    /// Jumps half the area at once, then repeats until `stop()`.
    public func startHalfPage(_ direction: ScrollDirection, in area: CGRect, via output: ScrollOutput) {
        repeatStep(every: Self.halfPageInterval, step(direction, distance: Self.halfPage(direction, of: area), via: output))
    }

    public func scrollToEdge(top: Bool, via output: ScrollOutput) {
        stop()
        switch output {
        case .accessibility(let control):
            // A one-shot command must not be dropped like a repeating tick.
            writer.submit(dropIfBusy: false) { control.scrollToEdge(top: top) }
        case .wheel:
            Self.post(Self.wheelDelta(top ? .up : .down, distance: Self.edgeDistance,
                                      naturalScrolling: Self.isNaturalScrolling()))
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step(_ direction: ScrollDirection, distance: Int32, via output: ScrollOutput) -> @MainActor () -> Void {
        switch output {
        case .accessibility(let control):
            let writer = self.writer
            return { writer.submit { control.scroll(direction, pixels: CGFloat(distance)) } }
        case .wheel:
            let delta = Self.wheelDelta(direction, distance: distance, naturalScrolling: Self.isNaturalScrolling())
            return { Self.post(delta) }
        }
    }

    private func repeatStep(every interval: TimeInterval, _ step: @escaping @MainActor () -> Void) {
        stop()
        step()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { step() }
        }
    }

    /// Positive wheel values move the content down/right toward the start,
    /// so scrolling down or right uses negative values. macOS also applies the
    /// user's natural-scrolling inversion to synthesized wheel events, so the
    /// sign is flipped back when it is on.
    nonisolated static func wheelDelta(_ direction: ScrollDirection, distance: Int32, naturalScrolling: Bool) -> ScrollDelta {
        let signed = naturalScrolling ? -distance : distance
        return switch direction {
        case .up: ScrollDelta(horizontal: 0, vertical: signed)
        case .down: ScrollDelta(horizontal: 0, vertical: -signed)
        case .left: ScrollDelta(horizontal: signed, vertical: 0)
        case .right: ScrollDelta(horizontal: -signed, vertical: 0)
        }
    }

    /// System Settings > Trackpad/Mouse > Natural scrolling, read on every
    /// scroll so a change applies immediately. On by default in macOS.
    nonisolated static func isNaturalScrolling(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }

    nonisolated static func halfPage(_ direction: ScrollDirection, of area: CGRect) -> Int32 {
        switch direction {
        case .up, .down: Int32(area.height / 2)
        case .left, .right: Int32(area.width / 2)
        }
    }

    private nonisolated static func post(_ delta: ScrollDelta) {
        CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: delta.vertical, wheel2: delta.horizontal, wheel3: 0
        )?.post(tap: .cghidEventTap)
    }
}

/// Runs accessibility writes off the main thread, one at a time. A tick that
/// arrives while the previous write is still running is dropped, so a slow
/// app never builds a backlog that keeps scrolling after the key is released.
private nonisolated final class AccessibilityWriter: Sendable {
    private let queue = DispatchQueue(label: "com.alvaldes.jump.scroll", qos: .userInteractive)
    private let busy = Atomic(false)

    /// - Parameter dropIfBusy: `true` for repeating ticks; `false` queues the
    ///   work behind the running write (one-shot commands like `G`).
    func submit(dropIfBusy: Bool = true, _ work: @escaping @Sendable () -> Void) {
        guard dropIfBusy else {
            queue.async(execute: work)
            return
        }
        guard !busy.exchange(true, ordering: .acquiring) else { return }
        queue.async {
            work()
            self.busy.store(false, ordering: .releasing)
        }
    }
}
