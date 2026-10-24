import CoreGraphics

/// An element the user can act on, with its visible frame.
public struct ScannedElement<Node: AccessibilityNode>: Sendable {
    public let node: Node
    public let role: String
    /// Visible part of the element in AX coordinates, clipped to its ancestors.
    public let frame: CGRect
}

public struct ScanResult<Node: AccessibilityNode>: Sendable {
    public let elements: [ScannedElement<Node>]
    /// Number of tree nodes whose attributes were read.
    public let visitedCount: Int
    /// `true` when a cap, the deadline or cancellation stopped the scan early.
    public let isTruncated: Bool
}

/// Walks an accessibility tree and collects actionable, visible elements.
///
/// Filtering rules are ported from Vimac (`ElementTree.swift`, GPL-3.0).
public nonisolated struct ElementScanner: Sendable {
    /// Actions that do not make an element worth a hint on their own.
    static let ignoredActions: Set<String> = [
        "AXShowMenu",
        "AXScrollToVisible",
        "AXShowDefaultUI",
        "AXShowAlternateUI",
    ]

    /// Containers that are never hinted themselves, only their content.
    static let excludedRoles: Set<String> = ["AXWindow", "AXScrollArea"]

    public var maxDepth: Int
    public var maxElements: Int

    public init(maxDepth: Int = 64, maxElements: Int = 5_000) {
        self.maxDepth = maxDepth
        self.maxElements = maxElements
    }

    public func scan<Node: AccessibilityNode>(root: Node, deadline: ContinuousClock.Instant) -> ScanResult<Node> {
        var state = State<Node>(deadline: deadline)
        visit(root, clip: nil, depth: 0, state: &state)
        return ScanResult(elements: state.elements, visitedCount: state.visitedCount, isTruncated: state.isTruncated)
    }

    private struct State<Node: AccessibilityNode> {
        let deadline: ContinuousClock.Instant
        var elements: [ScannedElement<Node>] = []
        var visitedCount = 0
        var isTruncated = false
    }

    private func visit<Node: AccessibilityNode>(
        _ node: Node,
        clip: CGRect?,
        depth: Int,
        state: inout State<Node>
    ) {
        guard !state.isTruncated else { return }
        guard depth <= maxDepth,
              state.visitedCount < maxElements,
              ContinuousClock.now < state.deadline,
              !Task.isCancelled
        else {
            state.isTruncated = true
            return
        }

        state.visitedCount += 1
        guard let attributes = node.attributes() else { return }

        // Prune elements (and their subtrees) entirely outside their ancestors.
        if let clip, !clip.intersects(attributes.frame) { return }
        let visibleFrame = clip.map { $0.intersection(attributes.frame) } ?? attributes.frame

        let element = ScannedElement(node: node, role: attributes.role, frame: visibleFrame)
        let isActionable = isActionable(attributes)
        if isActionable {
            state.elements.append(element)
        }

        let countBeforeChildren = state.elements.count
        for child in node.children(role: attributes.role) {
            visit(child, clip: visibleFrame, depth: depth + 1, state: &state)
        }

        // A row with nothing actionable inside is itself the target (e.g. a list item).
        if !isActionable, attributes.role == "AXRow", state.elements.count == countBeforeChildren {
            state.elements.append(element)
        }
    }

    private func isActionable(_ attributes: NodeAttributes) -> Bool {
        guard !Self.excludedRoles.contains(attributes.role) else { return false }
        return attributes.actions.contains { !Self.ignoredActions.contains($0) }
    }
}
