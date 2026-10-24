import CoreGraphics
import Testing
@testable import JumpKit

/// In-memory accessibility tree used instead of real `AXUIElement`s.
private nonisolated struct FakeNode: AccessibilityNode {
    let id: String
    let attrs: NodeAttributes?
    var actionNames: [String] = []
    let kids: [FakeNode]

    func attributes(prefetchingChildren: Bool) -> NodeAttributes? { attrs }
    func actions() -> [String] { actionNames }
    func children(role: String) -> [FakeNode] { kids }
}

private func node(
    _ id: String,
    role: String = "AXGroup",
    frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
    actions: [String] = [],
    _ children: [FakeNode] = []
) -> FakeNode {
    FakeNode(id: id, attrs: NodeAttributes(role: role, frame: frame), actionNames: actions, kids: children)
}

private func window(_ children: [FakeNode]) -> FakeNode {
    node("window", role: "AXWindow", frame: CGRect(x: 0, y: 0, width: 1000, height: 800), actions: ["AXRaise"], children)
}

private let farFuture = ContinuousClock.now.advanced(by: .seconds(60))

private func scannedIDs(_ root: FakeNode, scanner: ElementScanner = ElementScanner()) -> [String] {
    scanner.scan(root: root, deadline: farFuture).elements.map(\.node.id)
}

@Suite("ElementScanner")
struct ElementScannerTests {
    @Test func includesElementsWithAnActionAndSkipsInertOnes() {
        let root = window([
            node("button", role: "AXButton", actions: ["AXPress"]),
            node("label", role: "AXStaticText"),
        ])
        #expect(scannedIDs(root) == ["button"])
    }

    @Test func ignoresElementsWhoseOnlyActionsAreIgnored() {
        let root = window([
            node("menuOnly", actions: ["AXShowMenu", "AXScrollToVisible", "AXShowDefaultUI", "AXShowAlternateUI"]),
        ])
        #expect(scannedIDs(root).isEmpty)
    }

    @Test func standardControlsAreTargetsWithoutAskingForActions() {
        // Buttons, checkboxes, text fields... always have an action; skipping the
        // query saves one IPC round-trip per control.
        let root = window([node("button", role: "AXButton", actions: [])])
        #expect(scannedIDs(root) == ["button"])
    }

    @Test func pureContainersAreNeverTargets() {
        let root = window([node("toolbar", role: "AXToolbar", actions: ["AXPress"])])
        #expect(scannedIDs(root).isEmpty)
    }

    @Test func customNamedActionsDoNotMakeATarget() {
        // e.g. toolbar items expose "Name:Move next" to reorder the toolbar.
        let root = window([node("toolbarItem", role: "AXGroup", actions: ["Name:Move next\nTarget:0x0\nSelector:(null)"])])
        #expect(scannedIDs(root).isEmpty)
    }

    @Test func listRowsAreOneTargetInsteadOfTheirCells() {
        // Finder rows: an actionable cell plus a name field gave two hints per row.
        let root = window([
            node("outline", role: "AXOutline", [
                node("row", role: "AXRow", [
                    node("cell", role: "AXCell", actions: ["AXOpen"], [
                        node("icon", role: "AXImage"),
                        node("name", role: "AXTextField", actions: ["AXConfirm"]),
                    ]),
                ]),
            ]),
        ])
        #expect(scannedIDs(root) == ["row"])
    }

    @Test func controlsInsideRowsStayTargets() {
        let root = window([
            node("table", role: "AXTable", [
                node("row", role: "AXRow", [
                    node("cell", role: "AXCell", [node("toggle", role: "AXCheckBox")]),
                ]),
            ]),
        ])
        #expect(scannedIDs(root) == ["toggle"])
    }

    private func plainRow(_ id: String, y: CGFloat) -> FakeNode {
        node(id, role: "AXRow", frame: CGRect(x: 0, y: y, width: 400, height: 20), [
            node("\(id).cell", role: "AXCell", frame: CGRect(x: 0, y: y, width: 400, height: 20), [
                node("\(id).text", role: "AXStaticText", frame: CGRect(x: 0, y: y, width: 100, height: 20)),
            ]),
        ])
    }

    @Test func rowsAfterAPlainSampleAreTargetsWithoutReadingTheirContent() {
        let rows = (0..<5).map { plainRow("r\($0)", y: CGFloat($0) * 20) }
        let result = ElementScanner().scan(root: window([node("table", role: "AXTable", rows)]), deadline: farFuture)
        #expect(result.elements.map(\.node.id) == ["r0", "r1", "r2", "r3", "r4"])
        // window + table + 3 sampled rows x 3 nodes + 2 rows read alone.
        #expect(result.visitedCount == 2 + 9 + 2)
    }

    @Test func aControlInTheSampleMakesEveryRowBeReadInFull() {
        var rows = (0..<5).map { plainRow("r\($0)", y: CGFloat($0) * 20) }
        rows[1] = node("r1", role: "AXRow", frame: CGRect(x: 0, y: 20, width: 400, height: 20), [
            node("toggle1", role: "AXCheckBox", frame: CGRect(x: 0, y: 20, width: 20, height: 20)),
        ])
        rows[4] = node("r4", role: "AXRow", frame: CGRect(x: 0, y: 80, width: 400, height: 20), [
            node("toggle4", role: "AXCheckBox", frame: CGRect(x: 0, y: 80, width: 20, height: 20)),
        ])
        let ids = scannedIDs(window([node("table", role: "AXTable", rows)]))
        #expect(ids == ["r0", "toggle1", "r2", "r3", "toggle4"])
    }

    @Test func rowsLabelledByALeadingButtonStandInForIt() {
        // System Settings sidebar: every row is row > cell > button (the item's label).
        let rows = (0..<5).map { index -> FakeNode in
            let y = CGFloat(index) * 30
            return node("r\(index)", role: "AXRow", frame: CGRect(x: 0, y: y, width: 200, height: 28), [
                node("r\(index).cell", role: "AXCell", frame: CGRect(x: 0, y: y, width: 200, height: 28), [
                    node("r\(index).label", role: "AXButton", frame: CGRect(x: 12, y: y + 6, width: 60, height: 16)),
                ]),
            ])
        }
        let result = ElementScanner().scan(root: window([node("table", role: "AXOutline", frame: CGRect(x: 0, y: 0, width: 200, height: 400), rows)]), deadline: farFuture)
        #expect(result.elements.map(\.node.id) == ["r0.label", "r1.label", "r2.label", "r3", "r4"])
        #expect(result.visitedCount == 2 + 9 + 2)
    }

    @Test func neverIncludesWindowsOrScrollAreas() {
        let root = window([
            node("scroll", role: "AXScrollArea", actions: ["AXPress"], [
                node("link", role: "AXLink", actions: ["AXPress"]),
            ]),
        ])
        #expect(scannedIDs(root) == ["link"])
    }

    @Test func includesRowWithoutActionableDescendants() {
        let root = window([
            node("table", role: "AXTable", [
                node("plainRow", role: "AXRow", [node("text", role: "AXStaticText")]),
                node("rowWithButton", role: "AXRow", [node("rowButton", role: "AXButton", actions: ["AXPress"])]),
            ]),
        ])
        #expect(Set(scannedIDs(root)) == ["plainRow", "rowButton"])
    }

    @Test func prunesSubtreesOutsideTheAncestorClip() {
        let root = window([
            node("panel", frame: CGRect(x: 0, y: 0, width: 200, height: 200), [
                node("visible", frame: CGRect(x: 10, y: 10, width: 20, height: 20), actions: ["AXPress"]),
                node("offscreen", frame: CGRect(x: 500, y: 500, width: 20, height: 20), actions: ["AXPress"], [
                    node("offscreenChild", frame: CGRect(x: 510, y: 510, width: 5, height: 5), actions: ["AXPress"]),
                ]),
            ]),
        ])
        #expect(scannedIDs(root) == ["visible"])
    }

    @Test func clipsFramesToTheirAncestors() {
        let root = window([
            node("panel", frame: CGRect(x: 0, y: 0, width: 200, height: 200), [
                node("halfVisible", frame: CGRect(x: 150, y: 150, width: 100, height: 100), actions: ["AXPress"]),
            ]),
        ])
        let frames = ElementScanner().scan(root: root, deadline: farFuture).elements.map(\.frame)
        #expect(frames == [CGRect(x: 150, y: 150, width: 50, height: 50)])
    }

    @Test func skipsElementsThatDisappearedDuringTheScan() {
        let gone = FakeNode(id: "gone", attrs: nil, kids: [node("orphan", actions: ["AXPress"])])
        let root = window([gone, node("button", actions: ["AXPress"])])
        #expect(scannedIDs(root) == ["button"])
    }

    @Test func stopsAtTheElementCapAndReportsTruncation() {
        let buttons = (0..<10).map { node("b\($0)", actions: ["AXPress"]) }
        let result = ElementScanner(maxElements: 4).scan(root: window(buttons), deadline: farFuture)
        #expect(result.visitedCount == 4)
        #expect(result.isTruncated)
    }

    @Test func doesNotTreatAPartiallyScannedRowAsEmpty() {
        // The cap hits while visiting the row's children, so its content is unknown.
        let row = node("row", role: "AXRow", [
            node("text", role: "AXStaticText"),
            node("button", actions: ["AXPress"]),
        ])
        let result = ElementScanner(maxElements: 2).scan(root: window([row]), deadline: farFuture)
        #expect(result.isTruncated)
        #expect(result.elements.isEmpty)
    }

    @Test func doesNotDescendBelowTheDepthCap() {
        let deep = node("level1", [node("level2", [node("level3", actions: ["AXPress"])])])
        let result = ElementScanner(maxDepth: 2).scan(root: window([deep]), deadline: farFuture)
        #expect(result.elements.isEmpty)
        #expect(result.isTruncated)
    }

    @Test func depthCapSkipsOnlyTheDeepBranch() {
        let deep = node("level1", [node("level2", [node("level3", actions: ["AXPress"])])])
        let sibling = node("sibling", actions: ["AXPress"])
        let result = ElementScanner(maxDepth: 2).scan(root: window([deep, sibling]), deadline: farFuture)
        #expect(result.elements.map(\.node.id) == ["sibling"])
        #expect(result.isTruncated)
    }

    @Test func zeroSizeContainersDoNotHideTheirChildren() {
        let root = window([
            node("wrapper", frame: .zero, [
                node("button", frame: CGRect(x: 10, y: 10, width: 20, height: 20), actions: ["AXPress"]),
            ]),
        ])
        let elements = ElementScanner().scan(root: root, deadline: farFuture).elements
        #expect(elements.map(\.node.id) == ["button"])
        #expect(elements.map(\.frame) == [CGRect(x: 10, y: 10, width: 20, height: 20)])
    }

    @Test func stopsWhenTheDeadlineHasPassed() {
        let root = window([node("button", actions: ["AXPress"])])
        let result = ElementScanner().scan(root: root, deadline: .now.advanced(by: .seconds(-1)))
        #expect(result.elements.isEmpty)
        #expect(result.isTruncated)
    }

    @Test func completeScanIsNotTruncated() {
        let result = ElementScanner().scan(root: window([node("button", actions: ["AXPress"])]), deadline: farFuture)
        #expect(!result.isTruncated)
        #expect(result.elements.map(\.role) == ["AXGroup"])
    }
}
