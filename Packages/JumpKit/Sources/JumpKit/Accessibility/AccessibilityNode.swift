import CoreGraphics

/// One element of an accessibility tree.
///
/// Abstracts `AXUIElement` so the scanner can be tested with in-memory trees.
/// Implementations are called from a background task, never the main thread.
public protocol AccessibilityNode: Sendable {
    /// Role and frame in a single IPC round-trip.
    /// Returns `nil` when the element no longer exists.
    /// - Parameter prefetchingChildren: `false` when the scanner already knows
    ///   it will not descend, so implementations can skip fetching children.
    nonisolated func attributes(prefetchingChildren: Bool) -> NodeAttributes?

    /// Names of the actions the element supports. A separate round-trip, so
    /// the scanner only asks for visible elements that could become hints.
    nonisolated func actions() -> [String]

    /// Children to traverse; `role` lets tables and outlines return only visible rows.
    nonisolated func children(role: String) -> [Self]
}

public nonisolated struct NodeAttributes: Sendable, Equatable {
    public var role: String
    /// Frame in AX coordinates (origin at the top-left of the primary screen).
    public var frame: CGRect

    public nonisolated init(role: String, frame: CGRect) {
        self.role = role
        self.frame = frame
    }
}
