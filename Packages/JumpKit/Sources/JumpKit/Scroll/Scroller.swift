import CoreGraphics
import Foundation
import Synchronization

public nonisolated struct ScrollDelta: Sendable, Equatable {
    public let horizontal: Int32
    public let vertical: Int32
}

/// How scroll commands reach the app.
public nonisolated enum ScrollOutput<Control: ScrollControlling>: Sendable {
    /// Writes the area's scroll bar values: independent of the pointer.
    case accessibility(Control)
    /// Synthetic wheel events, delivered to whatever is under the pointer.
    case wheel
}

/// What scroll mode needs from a scroller (`Scroller` in production).
public protocol ScrollDriving: AnyObject {
    associatedtype Control: ScrollControlling
    /// Called on the main thread with the failing control when the app
    /// rejects an accessibility read or write.
    var onAccessibilityFailure: ((Control) -> Void)? { get set }
    func startSmooth(_ direction: ScrollDirection, via output: ScrollOutput<Control>)
    func startHalfPage(_ direction: ScrollDirection, in area: CGRect, via output: ScrollOutput<Control>)
    func scrollToEdge(top: Bool, via output: ScrollOutput<Control>)
    func stop()
}

/// How fast holding a direction key scrolls.
public nonisolated enum ScrollSpeed: String, CaseIterable, Sendable {
    case slow, normal, fast

    public var title: String {
        switch self {
        case .slow: "Slow"
        case .normal: "Normal"
        case .fast: "Fast"
        }
    }

    var pixelsPerTick: Int32 {
        switch self {
        case .slow: ScrollMetrics.smoothStep / 2
        case .normal: ScrollMetrics.smoothStep
        case .fast: ScrollMetrics.smoothStep * 2
        }
    }
}

/// Scroll speeds and the wheel-event math (port of Vimac's `ChunkyScroller`).
public nonisolated enum ScrollMetrics {
    /// Pixels per tick while a direction key is held, at 60 ticks per second.
    static let smoothStep: Int32 = 16
    static let smoothInterval: TimeInterval = 1.0 / 60
    /// Half-page jumps repeat at this pace while the key is held.
    static let halfPageInterval: TimeInterval = 0.25
    /// Large enough to reach either end of any document in one event (Vimac).
    static let edgeDistance = Int32(Int16.max)

    /// Positive wheel values move the content down/right toward the start,
    /// so scrolling down or right uses negative values. macOS also applies the
    /// user's natural-scrolling inversion to synthesized wheel events, so the
    /// sign is flipped back when it is on.
    static func wheelDelta(_ direction: ScrollDirection, distance: Int32, naturalScrolling: Bool) -> ScrollDelta {
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
    static func isNaturalScrolling(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }

    static func halfPage(_ direction: ScrollDirection, of area: CGRect) -> Int32 {
        switch direction {
        case .up, .down: Int32(area.height / 2)
        case .left, .right: Int32(area.width / 2)
        }
    }

    static func post(_ delta: ScrollDelta) {
        CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: delta.vertical, wheel2: delta.horizontal, wheel3: 0
        )?.post(tap: .cghidEventTap)
    }
}

/// Turns scroll commands into continuous, half-page or edge scrolling.
public final class Scroller<Control: ScrollControlling>: ScrollDriving {
    private var timer: Timer?
    private let writer = AccessibilityWriter()
    private let speed: () -> ScrollSpeed

    /// Not called when there is simply nothing to scroll.
    public var onAccessibilityFailure: ((Control) -> Void)?

    /// - Parameter speed: Read when a scroll starts, so a change applies to the next one.
    public init(speed: @escaping () -> ScrollSpeed = { .normal }) {
        self.speed = speed
    }

    /// Scrolls continuously until `stop()`.
    public func startSmooth(_ direction: ScrollDirection, via output: ScrollOutput<Control>) {
        repeatStep(every: ScrollMetrics.smoothInterval, step(direction, distance: speed().pixelsPerTick, via: output))
    }

    /// Jumps half the area at once, then repeats until `stop()`.
    public func startHalfPage(_ direction: ScrollDirection, in area: CGRect, via output: ScrollOutput<Control>) {
        repeatStep(every: ScrollMetrics.halfPageInterval,
                   step(direction, distance: ScrollMetrics.halfPage(direction, of: area), via: output))
    }

    public func scrollToEdge(top: Bool, via output: ScrollOutput<Control>) {
        stop()
        switch output {
        case .accessibility(let control):
            let report = failureReporter()
            // A one-shot command must not be dropped like a repeating tick.
            writer.submit(dropIfBusy: false) {
                if control.scrollToEdge(top: top) == .failed { report(control) }
            }
        case .wheel:
            ScrollMetrics.post(ScrollMetrics.wheelDelta(top ? .up : .down, distance: ScrollMetrics.edgeDistance,
                                                        naturalScrolling: ScrollMetrics.isNaturalScrolling()))
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step(_ direction: ScrollDirection, distance: Int32, via output: ScrollOutput<Control>) -> @MainActor () -> Void {
        switch output {
        case .accessibility(let control):
            let writer = self.writer
            let report = failureReporter()
            return {
                writer.submit {
                    if control.scroll(direction, pixels: CGFloat(distance)) == .failed { report(control) }
                }
            }
        case .wheel:
            let delta = ScrollMetrics.wheelDelta(direction, distance: distance,
                                                 naturalScrolling: ScrollMetrics.isNaturalScrolling())
            return { ScrollMetrics.post(delta) }
        }
    }

    /// A thread-safe way for background writes to reach `onAccessibilityFailure`.
    private func failureReporter() -> @Sendable (Control) -> Void {
        { [weak self] control in
            Task { @MainActor in self?.onAccessibilityFailure?(control) }
        }
    }

    private func repeatStep(every interval: TimeInterval, _ step: @escaping @MainActor () -> Void) {
        stop()
        step()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { step() }
        }
    }
}

/// Runs accessibility writes off the main thread, one at a time. A tick that
/// arrives while the previous write is still running is dropped, so a slow
/// app never builds a backlog that keeps scrolling after the key is released.
nonisolated final class AccessibilityWriter: Sendable {
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
