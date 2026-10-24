import CoreGraphics

/// The mouse pointer, in global CG coordinates (same origin as AX).
public nonisolated enum Pointer {
    public static var location: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Moves the pointer with a real mouse-moved event, so apps update hover
    /// state and scroll events go to the element now under it.
    public static func move(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}
