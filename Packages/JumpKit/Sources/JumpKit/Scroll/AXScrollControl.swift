import ApplicationServices
import CoreGraphics
import Foundation

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
public nonisolated struct AXScrollControl: @unchecked Sendable {
    // AXUIElement handles are immutable and the AX API is thread-safe.
    private let area: AXUIElement
    private let verticalBar: AXUIElement?
    private let horizontalBar: AXUIElement?
    private let visibleSize: CGSize

    /// `nil` when the area exposes no scroll bar whose value can be written.
    public static func make(for area: AXNode, frame: CGRect) -> AXScrollControl? {
        let vertical = writableBar(of: area.element, named: "AXVerticalScrollBar")
        let horizontal = writableBar(of: area.element, named: "AXHorizontalScrollBar")
        guard vertical != nil || horizontal != nil else { return nil }
        return AXScrollControl(area: area.element, verticalBar: vertical, horizontalBar: horizontal, visibleSize: frame.size)
    }

    /// Moves by `pixels` toward `direction`. Returns `false` if that axis cannot scroll.
    @discardableResult
    public func scroll(_ direction: ScrollDirection, pixels: CGFloat) -> Bool {
        let isVertical = direction == .up || direction == .down
        guard let bar = isVertical ? verticalBar : horizontalBar,
              let current: Double = AXNode.copyAttribute("AXValue", of: bar)
        else { return false }
        // The document can grow while it loads, so its size is read each time.
        let document = documentSize()
        let towardEnd = direction == .down || direction == .right
        guard let next = ScrollMath.nextValue(
            current: current,
            pixels: towardEnd ? pixels : -pixels,
            documentLength: isVertical ? document.height : document.width,
            visibleLength: isVertical ? visibleSize.height : visibleSize.width
        ) else { return false }
        return AXUIElementSetAttributeValue(bar, "AXValue" as CFString, NSNumber(value: next)) == .success
    }

    public func scrollToEdge(top: Bool) {
        guard let verticalBar else { return }
        AXUIElementSetAttributeValue(verticalBar, "AXValue" as CFString, NSNumber(value: top ? 0.0 : 1.0))
    }

    private func documentSize() -> CGSize {
        guard let contents: [AXUIElement] = AXNode.copyAttribute("AXContents", of: area),
              let document = contents.first,
              let value: AXValue = AXNode.copyAttribute("AXSize", of: document)
        else { return .zero }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : .zero
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
