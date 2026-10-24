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
        return ScanResult(
            elements: state.elements,
            visitedCount: state.visitedCount,
            isTruncated: state.isStopped || state.skippedBranches > 0
        )
    }

    private struct State<Node: AccessibilityNode> {
        let deadline: ContinuousClock.Instant
        var elements: [ScannedElement<Node>] = []
        var visitedCount = 0
        /// The element cap, deadline or cancellation ended the whole scan.
        var isStopped = false
        /// Subtrees left out because they were deeper than `maxDepth`.
        var skippedBranches = 0
    }

    private func visit<Node: AccessibilityNode>(
        _ node: Node,
        clip: CGRect?,
        depth: Int,
        state: inout State<Node>
    ) {
        guard !state.isStopped else { return }
        guard state.visitedCount < maxElements,
              ContinuousClock.now < state.deadline,
              !Task.isCancelled
        else {
            state.isStopped = true
            return
        }
        // Only this branch is too deep; its siblings are still scanned.
        guard depth <= maxDepth else {
            state.skippedBranches += 1
            return
        }

        state.visitedCount += 1
        guard let attributes = node.attributes() else { return }

        // Zero-size wrappers (common for AXGroup) are transparent: they neither
        // clip nor hide their children, and are not targets themselves.
        let frame = attributes.frame
        let hasArea = frame.width > 0 && frame.height > 0

        // Prune elements (and their subtrees) entirely outside their ancestors.
        if hasArea, let clip, !clip.intersects(frame) { return }
        let visibleFrame = hasArea ? (clip.map { $0.intersection(frame) } ?? frame) : nil

        let isTarget = visibleFrame != nil && isActionable(attributes)
        if isTarget, let visibleFrame {
            state.elements.append(ScannedElement(node: node, role: attributes.role, frame: visibleFrame))
        }

        let countBeforeChildren = state.elements.count
        let skippedBeforeChildren = state.skippedBranches
        for child in node.children(role: attributes.role) {
            visit(child, clip: visibleFrame ?? clip, depth: depth + 1, state: &state)
        }

        // A row with nothing actionable inside is itself the target (e.g. a list item).
        // Skipped when part of the row was not scanned: its content is then unknown.
        let rowFullyScanned = !state.isStopped && state.skippedBranches == skippedBeforeChildren
        if !isTarget, rowFullyScanned, attributes.role == "AXRow",
           state.elements.count == countBeforeChildren, let visibleFrame {
            state.elements.append(ScannedElement(node: node, role: attributes.role, frame: visibleFrame))
        }
    }

    private func isActionable(_ attributes: NodeAttributes) -> Bool {
        guard !Self.excludedRoles.contains(attributes.role) else { return false }
        return attributes.actions.contains { !Self.ignoredActions.contains($0) }
    }
}
