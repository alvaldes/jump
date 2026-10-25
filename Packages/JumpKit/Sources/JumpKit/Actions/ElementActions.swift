import ApplicationServices
import CoreGraphics

/// Performs the selected action on a scanned element.
public nonisolated enum ElementActions {
    /// Roles where "press" means "start typing here".
    static let textInputRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    @concurrent
    public static func perform(_ action: HintAction, on element: ScannedElement<AXNode>) async {
        let point = clickPoint(role: element.role, frame: element.frame)
        if case .press = action {
            press(element, fallbackPoint: point)
        } else {
            click(action, at: point)
        }
    }

    /// Synthesizes the action as pointer events at `point`: `press` is a
    /// plain left click. Also used by text search, which has no element to press.
    static func click(_ action: HintAction, at point: CGPoint) {
        switch action {
        case .press:
            click(at: point, button: .left, count: 1)
        case .rightClick:
            click(at: point, button: .right, count: 1)
        case .doubleClick:
            click(at: point, button: .left, count: 2)
        case .moveCursor:
            Pointer.move(to: point)
        }
    }

    /// Where synthesized clicks land, in global CG coordinates (same as AX).
    static func clickPoint(role: String, frame: CGRect) -> CGPoint {
        if role == "AXRow" {
            // Same spot as the row's hint, on its label.
            return HintAnchor(role: role, frame: frame).point
        }
        guard role == "AXLink" else { return CGPoint(x: frame.midX, y: frame.midY) }
        // Match the hint's bottom-left placement: multi-line links have no text at their center.
        let inset = CGSize(width: min(5, frame.width / 2), height: min(5, frame.height / 2))
        return CGPoint(x: frame.minX + inset.width, y: frame.maxY - inset.height)
    }

    /// Accessibility first: no cursor movement, and it works on partly covered
    /// elements. Falls back to a real click for elements without `AXPress`.
    private static func press(_ element: ScannedElement<AXNode>, fallbackPoint: CGPoint) {
        let target = element.node.element
        if textInputRoles.contains(element.role),
           AXUIElementSetAttributeValue(target, "AXFocused" as CFString, kCFBooleanTrue) == .success {
            return
        }
        if AXUIElementPerformAction(target, "AXPress" as CFString) == .success {
            return
        }
        click(at: fallbackPoint, button: .left, count: 1)
    }

    private static func click(at point: CGPoint, button: CGMouseButton, count: Int) {
        let (down, up): (CGEventType, CGEventType) = button == .right
            ? (.rightMouseDown, .rightMouseUp)
            : (.leftMouseDown, .leftMouseUp)
        Pointer.move(to: point)
        for clickState in 1...count {
            for type in [down, up] {
                guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
                else { continue }
                // Without an explicit click state a double click arrives as two single clicks.
                event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
                // Modifiers held to choose the action must not reach the target app (Vimac Utils).
                event.flags = []
                event.post(tap: .cghidEventTap)
            }
        }
    }

}
