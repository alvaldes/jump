import CoreGraphics
import Testing
@testable import JumpKit

@Suite("HintLabels")
struct HintLabelsTests {
    private let characters = HintLabels.defaultCharacters

    @Test func noElementsMeansNoLabels() {
        #expect(HintLabels.make(count: 0, characters: characters).isEmpty)
    }

    @Test func fewElementsGetSingleCharacterLabels() {
        let labels = HintLabels.make(count: 5, characters: characters)
        #expect(labels.count == 5)
        #expect(labels.allSatisfy { $0.count == 1 })
    }

    @Test(arguments: [1, 13, 14, 15, 100, 196, 197, 500])
    func labelsAreUniquePrefixFreeAndNearlyEqualInLength(count: Int) {
        let labels = HintLabels.make(count: count, characters: characters)

        #expect(labels.count == count)
        #expect(Set(labels).count == count)
        for label in labels {
            #expect(!labels.contains { $0 != label && $0.hasPrefix(label) }, "\(label) is a prefix of another label")
        }
        let lengths = labels.map(\.count)
        #expect(lengths.max()! - lengths.min()! <= 1)
    }

    @Test func labelsUseOnlyTheConfiguredCharactersInUppercase() {
        let labels = HintLabels.make(count: 50, characters: "ab")
        #expect(labels.allSatisfy { $0.allSatisfy { "AB".contains($0) } })
    }

    @Test func shorterLabelsComeFirst() {
        let lengths = HintLabels.make(count: 15, characters: characters).map(\.count)
        #expect(lengths == lengths.sorted())
    }
}

@Suite("HintAssigner")
struct HintAssignerTests {
    private nonisolated struct Node: AccessibilityNode {
        let id: String
        func attributes() -> NodeAttributes? { nil }
        func children(role: String) -> [Node] { [] }
    }

    private func element(_ id: String, x: CGFloat, y: CGFloat, role: String = "AXButton") -> ScannedElement<Node> {
        ScannedElement(node: Node(id: id), role: role, frame: CGRect(x: x, y: y, width: 40, height: 20))
    }

    @Test func assignsLabelsInReadingOrder() {
        let scrambled = [
            element("bottomRight", x: 300, y: 300),
            element("topRight", x: 300, y: 10),
            element("bottomLeft", x: 10, y: 300),
            element("topLeft", x: 10, y: 12),  // same visual row as topRight
        ]
        let hints = HintAssigner.assign(scrambled, characters: "sadf")
        #expect(hints.map(\.element.node.id) == ["topLeft", "topRight", "bottomLeft", "bottomRight"])
        #expect(hints.map(\.label) == HintLabels.make(count: 4, characters: "sadf"))
    }

    @Test func topLeftElementsGetTheShortestLabels() {
        let elements = (0..<15).map { element("e\($0)", x: 10, y: CGFloat($0) * 30) }
        let hints = HintAssigner.assign(elements.reversed(), characters: HintLabels.defaultCharacters)
        #expect(hints.first?.element.node.id == "e0")
        #expect(hints.first?.label.count == 1)
        #expect(hints.last?.element.node.id == "e14")
        #expect(hints.last?.label.count == 2)
    }

    @Test func linksAnchorAtBottomLeftOthersAtCenter() {
        let frame = CGRect(x: 100, y: 50, width: 40, height: 20)
        #expect(HintAnchor(role: "AXLink", frame: frame) == HintAnchor(point: CGPoint(x: 100, y: 70), alignment: .bottomLeading))
        #expect(HintAnchor(role: "AXButton", frame: frame) == HintAnchor(point: CGPoint(x: 120, y: 60), alignment: .center))
    }
}
