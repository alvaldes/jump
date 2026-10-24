import CoreGraphics

/// One element of an accessibility tree.
///
/// Abstracts `AXUIElement` so the scanner can be tested with in-memory trees.
/// Implementations are called from a background task, never the main thread.
public protocol AccessibilityNode: Sendable {
    /// Role, frame and actions in as few IPC round-trips as possible.
    /// Returns `nil` when the element no longer exists.
    nonisolated func attributes() -> NodeAttributes?

    /// Children to traverse; `role` lets tables and outlines return only visible rows.
    nonisolated func children(role: String) -> [Self]
}

public struct NodeAttributes: Sendable, Equatable {
    public var role: String
    /// Frame in AX coordinates (origin at the top-left of the primary screen).
    public var frame: CGRect
    public var actions: [String]

    public nonisolated init(role: String, frame: CGRect, actions: [String]) {
        self.role = role
        self.frame = frame
        self.actions = actions
    }
}
