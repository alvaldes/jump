import CoreGraphics
import Foundation

public nonisolated struct ScrollDelta: Sendable, Equatable {
    public let horizontal: Int32
    public let vertical: Int32
}

/// Posts synthetic scroll-wheel events to whatever is under the cursor
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

    public init() {}

    /// Scrolls continuously until `stop()`.
    public func startSmooth(_ direction: ScrollDirection) {
        repeatScroll(Self.wheelDelta(direction, distance: Self.smoothStep), every: Self.smoothInterval)
    }

    /// Jumps half the area at once, then repeats until `stop()`.
    public func startHalfPage(_ direction: ScrollDirection, in area: CGRect) {
        let distance = Self.halfPage(direction, of: area)
        repeatScroll(Self.wheelDelta(direction, distance: distance), every: Self.halfPageInterval)
    }

    public func scrollToEdge(top: Bool) {
        stop()
        Self.post(Self.wheelDelta(top ? .up : .down, distance: Self.edgeDistance))
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func repeatScroll(_ delta: ScrollDelta, every interval: TimeInterval) {
        stop()
        Self.post(delta)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Self.post(delta)
        }
    }

    /// Positive wheel values move the content down/right toward the start,
    /// so scrolling down or right uses negative values.
    nonisolated static func wheelDelta(_ direction: ScrollDirection, distance: Int32) -> ScrollDelta {
        switch direction {
        case .up: ScrollDelta(horizontal: 0, vertical: distance)
        case .down: ScrollDelta(horizontal: 0, vertical: -distance)
        case .left: ScrollDelta(horizontal: distance, vertical: 0)
        case .right: ScrollDelta(horizontal: -distance, vertical: 0)
        }
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
