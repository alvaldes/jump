import AppKit

/// Converts between the two global coordinate systems macOS uses.
///
/// - AX / Core Graphics: origin at the top-left of the primary screen, y grows down.
/// - AppKit (`NSScreen`, `NSWindow`): origin at the bottom-left of the primary screen, y grows up.
///
/// Both are anchored to the primary screen (`NSScreen.screens.first`), so its
/// height is all that is needed, whatever the multi-monitor arrangement.
public nonisolated enum ScreenGeometry {
    public static func appKitRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func appKitPoint(fromAX point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    public static func axRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

extension ScreenGeometry {
    /// Every display's frame in AX coordinates.
    @MainActor
    public static func screenFramesInAXCoordinates() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map { axRect(fromAppKit: $0.frame, primaryScreenHeight: primaryHeight) }
    }
}
