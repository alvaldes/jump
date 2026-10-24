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
    /// Their actions are not even queried, saving an IPC round-trip each.
    static let excludedRoles: Set<String> = [
        "AXWindow", "AXScrollArea",  // Vimac
        "AXSplitGroup", "AXSplitter", "AXOutline", "AXTable", "AXList", "AXScrollBar",
        "AXValueIndicator", "AXToolbar", "AXUnknown", "AXLayoutArea", "AXWebArea",
    ]

    /// Standard controls always expose a primary action, so they are targets
    /// without querying their actions (one IPC round-trip saved per control).
    static let actionableRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXDisclosureTriangle", "AXLink", "AXTextField", "AXTextArea", "AXComboBox",
        "AXSlider", "AXIncrementor", "AXColorWell",
    ]

    /// Inside a list row only these stay separate targets; cells, labels and
    /// icons are covered by the row itself (one hint per row, no IPC for them).
    static let rowControlRoles: Set<String> = actionableRoles.subtracting(["AXTextField", "AXTextArea"])

    /// Rows of one table share their structure: when this many rows contain no
    /// control, the remaining rows are hinted without reading their content.
    static let rowSampleSize = 3

    /// Accessibility custom actions ("Name:…") are secondary commands, like
    /// reordering a toolbar, not a reason to hint an element.
    private static let customActionPrefix = "Name:"

    public var maxDepth: Int
    public var maxElements: Int

    public init(maxDepth: Int = 64, maxElements: Int = 5_000) {
        self.maxDepth = maxDepth
        self.maxElements = maxElements
    }

    /// - Parameter isCancelled: Polled between nodes; defaults to the current task's cancellation.
    public func scan<Node: AccessibilityNode>(
        root: Node,
        deadline: ContinuousClock.Instant,
        isCancelled: () -> Bool = { Task.isCancelled }
    ) -> ScanResult<Node> {
        var state = State<Node>(deadline: deadline)
        visit(root, clip: nil, depth: 0, inRow: false, isCancelled: isCancelled, state: &state)
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

    /// Returns the node's visible frame, or `nil` when it was not scanned.
    @discardableResult
    private func visit<Node: AccessibilityNode>(
        _ node: Node,
        clip: CGRect?,
        depth: Int,
        inRow: Bool,
        readsContent: Bool = true,
        isCancelled: () -> Bool,
        state: inout State<Node>
    ) -> CGRect? {
        guard !state.isStopped else { return nil }
        guard state.visitedCount < maxElements,
              ContinuousClock.now < state.deadline,
              !isCancelled()
        else {
            state.isStopped = true
            return nil
        }
        // Only this branch is too deep; its siblings are still scanned.
        guard depth <= maxDepth else {
            state.skippedBranches += 1
            return nil
        }

        state.visitedCount += 1
        guard let attributes = node.attributes(prefetchingChildren: readsContent) else { return nil }

        // Zero-size wrappers (common for AXGroup) are transparent: they neither
        // clip nor hide their children, and are not targets themselves.
        let frame = attributes.frame
        let hasArea = frame.width > 0 && frame.height > 0

        // Prune elements (and their subtrees) entirely outside their ancestors.
        if hasArea, let clip, !clip.intersects(frame) { return nil }
        let visibleFrame = hasArea ? (clip.map { $0.intersection(frame) } ?? frame) : nil

        let isTarget = visibleFrame != nil && isActionable(node, role: attributes.role, inRow: inRow)
        if isTarget, let visibleFrame {
            state.elements.append(ScannedElement(node: node, role: attributes.role, frame: visibleFrame))
        }

        let countBeforeChildren = state.elements.count
        let skippedBeforeChildren = state.skippedBranches
        let childClip = visibleFrame ?? clip
        let childInRow = inRow || attributes.role == "AXRow"
        if !readsContent {
            // A row past a plain sample: its content is assumed to hold no control.
        } else if attributes.role == "AXWebArea", let targets = node.webTargets() {
            for target in targets {
                visitWebTarget(target, clip: childClip, isCancelled: isCancelled, state: &state)
            }
        } else if attributes.role == "AXTable" || attributes.role == "AXOutline" {
            var readsLaterRows = false
            for (index, row) in node.children(role: attributes.role).enumerated() {
                let countBeforeRow = state.elements.count
                let isSample = index < Self.rowSampleSize
                let rowFrame = visit(row, clip: childClip, depth: depth + 1, inRow: childInRow,
                                     readsContent: isSample || readsLaterRows, isCancelled: isCancelled, state: &state)
                if isSample, !Self.rowStandsIn(for: state.elements[countBeforeRow...], rowFrame: rowFrame) {
                    readsLaterRows = true
                }
            }
        } else {
            for child in node.children(role: attributes.role) {
                visit(child, clip: childClip, depth: depth + 1, inRow: childInRow, isCancelled: isCancelled, state: &state)
            }
        }

        // A row with nothing actionable inside is itself the target (e.g. a list item).
        // Skipped when part of the row was not scanned: its content is then unknown.
        let rowFullyScanned = !state.isStopped && state.skippedBranches == skippedBeforeChildren
        if !isTarget, rowFullyScanned, attributes.role == "AXRow",
           !state.elements[countBeforeChildren...].contains(where: Self.coversRow), let visibleFrame {
            state.elements.append(ScannedElement(node: node, role: attributes.role, frame: visibleFrame))
        }
        return visibleFrame
    }

    /// Adds one result of a web-area search. The search keys already define the
    /// result as interactive, so only images (also matched by the graphic key,
    /// mostly decorative) must prove they are pressable.
    private func visitWebTarget<Node: AccessibilityNode>(
        _ node: Node,
        clip: CGRect?,
        isCancelled: () -> Bool,
        state: inout State<Node>
    ) {
        guard !state.isStopped else { return }
        guard state.visitedCount < maxElements, ContinuousClock.now < state.deadline, !isCancelled() else {
            state.isStopped = true
            return
        }
        state.visitedCount += 1
        guard let attributes = node.attributes(prefetchingChildren: false),
              attributes.frame.width > 0, attributes.frame.height > 0
        else { return }
        if let clip, !clip.intersects(attributes.frame) { return }
        if attributes.role == "AXImage", !node.actions().contains("AXPress") { return }
        let frame = clip.map { $0.intersection(attributes.frame) } ?? attributes.frame
        state.elements.append(ScannedElement(node: node, role: attributes.role, frame: frame))
    }

    /// Whether a sampled row can represent its own content, so later rows of
    /// the same table need not be read: it holds no control, or only the
    /// button that labels it at its leading edge (System Settings sidebar).
    private static func rowStandsIn<Node>(for added: ArraySlice<ScannedElement<Node>>, rowFrame: CGRect?) -> Bool {
        let controls = added.filter(coversRow)
        guard let control = controls.first else { return true }
        guard controls.count == 1, control.role == "AXButton", let rowFrame else { return false }
        return control.frame.minX - rowFrame.minX <= leadingLabelInset
    }

    /// Whether a target found inside a row replaces the row's own hint. A
    /// disclosure triangle only expands the row, so the row stays a target.
    private static func coversRow<Node>(_ element: ScannedElement<Node>) -> Bool {
        element.role != "AXRow" && element.role != "AXDisclosureTriangle"
    }

    /// How far from a row's leading edge its label button may start.
    private static let leadingLabelInset: CGFloat = 40

    private func isActionable<Node: AccessibilityNode>(_ node: Node, role: String, inRow: Bool) -> Bool {
        // Decided by role when possible to save the round-trip.
        if inRow { return Self.rowControlRoles.contains(role) }
        // Rows become targets through the row rule in `visit`, never on their own.
        if role == "AXRow" || Self.excludedRoles.contains(role) { return false }
        if Self.actionableRoles.contains(role) { return true }
        return node.actions().contains { action in
            !Self.ignoredActions.contains(action) && !action.hasPrefix(Self.customActionPrefix)
        }
    }
}
