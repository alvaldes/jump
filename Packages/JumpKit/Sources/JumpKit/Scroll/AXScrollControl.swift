import ApplicationServices
import CoreGraphics
import Foundation

/// A scroll area with its accessibility control, prepared off the main thread.
public nonisolated struct ScrollTarget: Sendable {
    public let area: ScrollArea<AXNode>
    /// `nil` when the area can only be scrolled with wheel events.
    public var control: AXScrollControl?
}

/// What happened to one scroll request.
public nonisolated enum ScrollOutcome: Sendable, Equatable {
    case scrolled
    /// Nothing to do: no scroll bar on that axis, or the content fits.
    case unavailable
    /// The app rejected the read or write: switch to wheel events.
    case failed
}

/// Converts a pixel distance into a scroll bar value (0 = start, 1 = end).
public nonisolated enum ScrollMath {
    /// Returns `nil` when the content fits and cannot scroll.
    public static func nextValue(current: Double, pixels: CGFloat, documentLength: CGFloat, visibleLength: CGFloat) -> Double? {
        let travel = documentLength - visibleLength
        guard travel > 0 else { return nil }
        return min(1, max(0, current + Double(pixels / travel)))
    }
}

/// Scrolls an `AXScrollArea` by writing its scroll bars' values through the
/// accessibility API. Unlike wheel events, this does not depend on what is
/// under the pointer, so the user can move the mouse freely.
public nonisolated struct AXScrollControl: @unchecked Sendable, Equatable {
    // AXUIElement handles are immutable and the AX API is thread-safe.
    private let area: AXUIElement
    private let verticalBar: AXUIElement?
    private let horizontalBar: AXUIElement?
    private let visibleSize: CGSize

    /// `nil` when the area exposes no writable scroll bar or no document size;
    /// the caller then falls back to wheel events.
    public static func make(for area: AXNode) -> AXScrollControl? {
        let vertical = writableBar(of: area.element, named: "AXVerticalScrollBar")
        let horizontal = writableBar(of: area.element, named: "AXHorizontalScrollBar")
        guard vertical != nil || horizontal != nil,
              // The real viewport, not the frame clipped to the screen, so a
              // pixel and half a page mean what they say.
              let viewport = size(of: area.element), viewport.width > 0, viewport.height > 0
        else { return nil }
        let control = AXScrollControl(area: area.element, verticalBar: vertical, horizontalBar: horizontal, visibleSize: viewport)
        // Without a readable document size pixel steps cannot be converted.
        guard control.documentSize() != .zero else { return nil }
        return control
    }

    /// Two controls are equal when they drive the same scroll area.
    public static func == (lhs: AXScrollControl, rhs: AXScrollControl) -> Bool {
        CFEqual(lhs.area, rhs.area)
    }

    /// Moves by `pixels` toward `direction`.
    @discardableResult
    public func scroll(_ direction: ScrollDirection, pixels: CGFloat) -> ScrollOutcome {
        let isVertical = direction == .up || direction == .down
        // `h`/`l` on a list that only scrolls vertically is not an error.
        guard let bar = isVertical ? verticalBar : horizontalBar else { return .unavailable }
        guard let current: Double = AXNode.copyAttribute("AXValue", of: bar) else { return .failed }
        // The document can grow while it loads, so its size is read each time.
        let document = documentSize()
        guard document != .zero else { return .failed }
        let towardEnd = direction == .down || direction == .right
        guard let next = ScrollMath.nextValue(
            current: current,
            pixels: towardEnd ? pixels : -pixels,
            documentLength: isVertical ? document.height : document.width,
            visibleLength: isVertical ? visibleSize.height : visibleSize.width
        ) else { return .unavailable }
        return AXUIElementSetAttributeValue(bar, "AXValue" as CFString, NSNumber(value: next)) == .success
            ? .scrolled : .failed
    }

    @discardableResult
    public func scrollToEdge(top: Bool) -> ScrollOutcome {
        guard let verticalBar else { return .unavailable }
        return AXUIElementSetAttributeValue(verticalBar, "AXValue" as CFString, NSNumber(value: top ? 0.0 : 1.0)) == .success
            ? .scrolled : .failed
    }

    private func documentSize() -> CGSize {
        guard let contents: [AXUIElement] = AXNode.copyAttribute("AXContents", of: area),
              let document = contents.first
        else { return .zero }
        return Self.size(of: document) ?? .zero
    }

    private static func size(of element: AXUIElement) -> CGSize? {
        guard let value: AXValue = AXNode.copyAttribute("AXSize", of: element) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private static func writableBar(of area: AXUIElement, named attribute: String) -> AXUIElement? {
        guard let bar: AXUIElement = AXNode.copyAttribute(attribute, of: area) else { return nil }
        AXUIElementSetMessagingTimeout(bar, AXNode.messagingTimeout)
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(bar, "AXValue" as CFString, &settable) == .success, settable.boolValue
        else { return nil }
        return bar
    }
}
