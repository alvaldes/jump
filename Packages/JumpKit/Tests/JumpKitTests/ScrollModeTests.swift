import CoreGraphics
import Testing
@testable import JumpKit

@Suite("ScrollInput")
struct ScrollInputTests {
    private func command(for keys: [ScrollKey]) -> ScrollInputResult {
        var input = ScrollInput()
        var result = ScrollInputResult.ignored
        for key in keys { result = input.handle(key) }
        return result
    }

    @Test(arguments: [
        ("h", ScrollCommand.scroll(.left)), ("j", .scroll(.down)), ("k", .scroll(.up)), ("l", .scroll(.right)),
        ("d", .halfPage(.down)), ("u", .halfPage(.up)), ("G", .bottom),
    ] as [(Character, ScrollCommand)])
    func singleKeysMapToVimMotions(key: Character, expected: ScrollCommand) {
        #expect(command(for: [.character(key)]) == .command(expected))
    }

    @Test func ggGoesToTheTop() {
        var input = ScrollInput()
        #expect(input.handle(.character("g")) == .pending)
        #expect(input.handle(.character("g")) == .command(.top))
    }

    @Test func anInterruptedSequenceStartsOver() {
        var input = ScrollInput()
        _ = input.handle(.character("g"))
        #expect(input.handle(.character("x")) == .ignored)
        #expect(input.handle(.character("j")) == .command(.scroll(.down)))
    }

    @Test func resetDropsAPendingSequence() {
        var input = ScrollInput()
        _ = input.handle(.character("g"))
        input.reset()
        #expect(input.handle(.character("g")) == .pending)
    }

    @Test func tabCyclesAreasAndEscapeExits() {
        #expect(command(for: [.tab]) == .command(.nextArea))
        #expect(command(for: [.escape]) == .command(.exit))
    }

    @Test func otherKeysAreIgnored() {
        #expect(command(for: [.character("x")]) == .ignored)
    }
}

@Suite("ScrollAreaFinder")
struct ScrollAreaFinderTests {
    private nonisolated struct Node: AccessibilityNode {
        let id: String
        let role: String
        let frame: CGRect
        var kids: [Node] = []

        func attributes(prefetchingChildren: Bool) -> NodeAttributes? { NodeAttributes(role: role, frame: frame) }
        func actions() -> [String] { [] }
        func children(role: String) -> [Node] { kids }
    }

    private let farFuture = ContinuousClock.now.advanced(by: .seconds(60))

    private func window(_ kids: [Node]) -> Node {
        Node(id: "window", role: "AXWindow", frame: CGRect(x: 0, y: 0, width: 1000, height: 800), kids: kids)
    }

    private func ids(_ root: Node) -> [String] {
        ScrollAreaFinder().find(in: root, deadline: farFuture).map(\.node.id)
    }

    @Test func largestScrollAreasComeFirstThenTheWindow() {
        let root = window([
            Node(id: "sidebar", role: "AXScrollArea", frame: CGRect(x: 0, y: 0, width: 200, height: 800)),
            Node(id: "content", role: "AXSplitGroup", frame: CGRect(x: 200, y: 0, width: 800, height: 800), kids: [
                Node(id: "main", role: "AXScrollArea", frame: CGRect(x: 200, y: 0, width: 800, height: 800)),
            ]),
        ])
        #expect(ids(root) == ["main", "sidebar", "window"])
    }

    @Test func scrollAreasOutsideTheWindowAreIgnored() {
        let root = window([Node(id: "hidden", role: "AXScrollArea", frame: CGRect(x: 2000, y: 0, width: 300, height: 300))])
        #expect(ids(root) == ["window"])
    }

    @Test func webContentAndTablesAreNotSearched() {
        // Walking a web page or thousands of rows would cost far more than it finds.
        let root = window([
            Node(id: "page", role: "AXScrollArea", frame: CGRect(x: 0, y: 0, width: 1000, height: 800), kids: [
                Node(id: "web", role: "AXWebArea", frame: CGRect(x: 0, y: 0, width: 1000, height: 800), kids: [
                    Node(id: "innerWebScroll", role: "AXScrollArea", frame: CGRect(x: 10, y: 10, width: 100, height: 100)),
                ]),
                Node(id: "table", role: "AXTable", frame: CGRect(x: 0, y: 0, width: 1000, height: 800), kids: [
                    Node(id: "cellScroll", role: "AXScrollArea", frame: CGRect(x: 10, y: 10, width: 100, height: 100)),
                ]),
            ]),
        ])
        #expect(ids(root) == ["page", "window"])
    }
}
