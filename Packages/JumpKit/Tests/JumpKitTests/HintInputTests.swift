import Testing
@testable import JumpKit

@Suite("HintInput")
struct HintInputTests {
    private let labels = ["A", "S", "DA", "DS"]

    @Test func typingAFullLabelMatchesIt() {
        var input = HintInput(labels: labels)
        #expect(input.handle(.character("s")) == .matched("S"))
    }

    @Test func typingAPrefixFiltersAndKeepsWaiting() {
        var input = HintInput(labels: labels)
        #expect(input.handle(.character("d")) == .filtering("D"))
        #expect(input.typed == "D")
        #expect(input.handle(.character("a")) == .matched("DA"))
    }

    @Test func typingSomethingThatMatchesNothingCancels() {
        var input = HintInput(labels: labels)
        #expect(input.handle(.character("x")) == .cancelled)
    }

    @Test func escapeCancels() {
        var input = HintInput(labels: labels)
        _ = input.handle(.character("d"))
        #expect(input.handle(.escape) == .cancelled)
    }

    @Test func deleteRemovesTheLastTypedCharacter() {
        var input = HintInput(labels: labels)
        _ = input.handle(.character("d"))
        #expect(input.handle(.backspace) == .filtering(""))
        #expect(input.typed.isEmpty)
    }

    @Test func deleteWithNothingTypedIsIgnored() {
        var input = HintInput(labels: labels)
        #expect(input.handle(.backspace) == .ignored)
    }

    @Test func spaceRotatesOverlappingHints() {
        var input = HintInput(labels: labels)
        #expect(input.handle(.space) == .rotate)
    }
}

@Suite("HintAction")
struct HintActionTests {
    @Test func noModifierPerformsThePrimaryAction() {
        #expect(HintAction(shift: false, command: false, option: false) == .press)
    }

    @Test func shiftRightClicks() {
        #expect(HintAction(shift: true, command: false, option: false) == .rightClick)
    }

    @Test func commandDoubleClicks() {
        #expect(HintAction(shift: false, command: true, option: false) == .doubleClick)
    }

    @Test func optionOnlyMovesTheCursor() {
        #expect(HintAction(shift: false, command: false, option: true) == .moveCursor)
    }
}
