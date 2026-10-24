import CoreGraphics
import Testing
@testable import JumpKit

/// In-memory accessibility tree used instead of real `AXUIElement`s.
private nonisolated struct FakeNode: AccessibilityNode {
    let id: String
    let attrs: NodeAttributes?
    let kids: [FakeNode]

    func attributes() -> NodeAttributes? { attrs }
    func children(role: String) -> [FakeNode] { kids }
}

private func node(
    _ id: String,
    role: String = "AXGroup",
    frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
    actions: [String] = [],
    _ children: [FakeNode] = []
) -> FakeNode {
    FakeNode(id: id, attrs: NodeAttributes(role: role, frame: frame, actions: actions), kids: children)
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
