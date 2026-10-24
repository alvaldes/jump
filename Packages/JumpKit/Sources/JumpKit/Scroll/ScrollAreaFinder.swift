import CoreGraphics

public struct ScrollArea<Node: AccessibilityNode>: Sendable {
    public let node: Node
    /// Visible part of the area in AX coordinates.
    public let frame: CGRect
}

/// Finds the scrollable regions of a window, largest first, with the window
/// itself last as a fallback (port of Vimac's `QueryScrollAreasService`).
public nonisolated struct ScrollAreaFinder: Sendable {
    /// Content that may hold many nodes but no useful nested scroll area.
    static let unsearchedRoles: Set<String> = ["AXWebArea", "AXTable", "AXOutline", "AXList", "AXBrowser"]

    public var maxDepth: Int
    public var maxNodes: Int

    public init(maxDepth: Int = 32, maxNodes: Int = 1_500) {
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
    }

    public func find<Node: AccessibilityNode>(in window: Node, deadline: ContinuousClock.Instant) -> [ScrollArea<Node>] {
        guard let attributes = window.attributes(prefetchingChildren: true) else { return [] }
        var areas: [ScrollArea<Node>] = []
        var visited = 1
        for child in window.children(role: attributes.role) {
            search(child, clip: attributes.frame, depth: 1, deadline: deadline, visited: &visited, areas: &areas)
        }
        let largestFirst = areas.sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
        return largestFirst + [ScrollArea(node: window, frame: attributes.frame)]
    }

    private func search<Node: AccessibilityNode>(
        _ node: Node,
        clip: CGRect,
        depth: Int,
        deadline: ContinuousClock.Instant,
        visited: inout Int,
        areas: inout [ScrollArea<Node>]
    ) {
        guard depth <= maxDepth, visited < maxNodes, ContinuousClock.now < deadline else { return }
        visited += 1
        guard let attributes = node.attributes(prefetchingChildren: true) else { return }
        let frame = attributes.frame
        // Zero-size wrappers are transparent, as in the hint scanner.
        let hasArea = frame.width > 0 && frame.height > 0
        if hasArea, !clip.intersects(frame) { return }
        let visible = hasArea ? clip.intersection(frame) : clip

        if attributes.role == "AXScrollArea", hasArea {
            areas.append(ScrollArea(node: node, frame: visible))
        }
        guard !Self.unsearchedRoles.contains(attributes.role) else { return }
        for child in node.children(role: attributes.role) {
            search(child, clip: visible, depth: depth + 1, deadline: deadline, visited: &visited, areas: &areas)
        }
    }
}
