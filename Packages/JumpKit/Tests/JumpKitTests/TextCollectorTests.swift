import CoreGraphics
import Foundation
import Testing
@testable import JumpKit

@Suite("TextCollector decisions")
struct TextCollectorTests {
    @Test(arguments: ["AXStaticText", "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"])
    func textRolesShowTheirValue(role: String) {
        #expect(TextCollector.visibleText(role: role, value: "Hello", title: "Label") == "Hello")
    }

    @Test(arguments: ["AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXLink"])
    func controlsShowTheirTitle(role: String) {
        #expect(TextCollector.visibleText(role: role, value: "1", title: "Save") == "Save")
    }

    @Test func otherRolesShowNothing() {
        // Groups and images only carry labels nobody sees.
        #expect(TextCollector.visibleText(role: "AXGroup", value: "x", title: "Sidebar") == nil)
        #expect(TextCollector.visibleText(role: "AXImage", value: nil, title: "Icon") == nil)
    }

    @Test func blankTextIsSkippedButSpacesAreKept() {
        #expect(TextCollector.visibleText(role: "AXStaticText", value: " \n ", title: nil) == nil)
        #expect(TextCollector.visibleText(role: "AXButton", value: nil, title: nil) == nil)
        // Ranges are UTF-16 offsets into the full AXValue, so it is never trimmed.
        #expect(TextCollector.visibleText(role: "AXStaticText", value: "  indented", title: nil) == "  indented")
    }

    @Test func textInputsAreEditable() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            #expect(TextCollector.isEditable(role: role), "\(role)")
        }
        #expect(!TextCollector.isEditable(role: "AXStaticText"))
        #expect(!TextCollector.isEditable(role: "AXButton"))
    }

    private static let frame = CGRect(x: 0, y: 0, width: 200, height: 20)

    @Test(arguments: ["AXButton", "AXCheckBox", "AXLink", "AXMenuItem"])
    func controlTitlesAreNotMeasuredAsValueRanges(role: String) throws {
        // AXBoundsForRange reads AXValue, so a range into the title would measure the wrong text.
        let run = try #require(TextCollector.run(role: role, frame: Self.frame, value: "1", title: "Save", node: "n"))
        #expect(run.text == "Save")
        #expect(run.source == .title)
        #expect(!TextCollector.measuresWordBounds(run))
    }

    @Test(arguments: ["AXStaticText", "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"])
    func valueTextIsStillMeasured(role: String) throws {
        let run = try #require(TextCollector.run(role: role, frame: Self.frame, value: "Hello", title: "Label", node: "n"))
        #expect(run.text == "Hello")
        #expect(run.source == .value)
        #expect(run.isEditable == TextCollector.isEditable(role: role))
        #expect(TextCollector.measuresWordBounds(run))
    }

    @Test func nodesWithoutVisibleTextAddNoRun() {
        #expect(TextCollector.run(role: "AXGroup", frame: Self.frame, value: "x", title: "Sidebar", node: "n") == nil)
        #expect(TextCollector.run(role: "AXButton", frame: Self.frame, value: nil, title: " ", node: "n") == nil)
    }

    private func match(editable: Bool) -> TextMatch<String> {
        let run = TextRun(text: "hello world", frame: CGRect(x: 0, y: 0, width: 200, height: 20),
                          role: editable ? "AXTextField" : "AXStaticText", isEditable: editable, node: "n")
        return TextMatch(run: run, range: NSRange(location: 6, length: 5), frame: CGRect(x: 60, y: 0, width: 50, height: 20))
    }

    @Test func pressInATextInputPlacesTheCaretAtTheMatch() {
        #expect(TextCollector.plan(.press, for: match(editable: true)) == .placeCaret(location: 6))
    }

    @Test(arguments: [HintAction.rightClick, .doubleClick, .moveCursor])
    func modifiersInATextInputStillClick(action: HintAction) {
        #expect(TextCollector.plan(action, for: match(editable: true)) == .click(action, at: CGPoint(x: 85, y: 10)))
    }

    @Test(arguments: [HintAction.press, .rightClick, .doubleClick, .moveCursor])
    func elsewhereTheJumpClicksTheMatchCenter(action: HintAction) {
        #expect(TextCollector.plan(action, for: match(editable: false)) == .click(action, at: CGPoint(x: 85, y: 10)))
    }
}
