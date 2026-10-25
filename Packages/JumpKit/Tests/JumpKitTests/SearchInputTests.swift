import Testing
@testable import JumpKit

@Suite("SearchInput")
struct SearchInputTests {
    private var input = SearchInput()

    private func key(_ keyCode: UInt16, _ characters: String = "", typed: String? = nil, shift: Bool = false,
                     command: Bool = false, option: Bool = false, control: Bool = false) -> KeyPress {
        KeyPress(keyCode: keyCode, characters: characters, typedCharacters: typed, shift: shift, command: command,
                 option: option, control: control)
    }

    @Test mutating func charactersAppendToTheQuery() {
        #expect(input.handle(key(1, "s")) == .edited("s"))
        #expect(input.handle(key(0, "A", shift: true)) == .edited("sA"))
        #expect(input.handle(key(49, " ")) == .edited("sA "))
        #expect(input.query == "sA ")
    }

    @Test mutating func optionStillTypes() {
        #expect(input.handle(key(1, "s", option: true)) == .edited("s"))
    }

    @Test mutating func optionTypesWhatTheLayoutProduces() {
        // ⌥2 on a Spanish layout.
        #expect(input.handle(key(19, "2", typed: "@", option: true)) == .edited("@"))
        #expect(input.handle(key(31, "o", typed: "ø", option: true)) == .edited("@ø"))
    }

    /// What the layout produced is what goes in the box, with or without ⌥
    /// (Caps Lock gives "S"; matching ignores case either way).
    @Test mutating func whatTheLayoutTypedIsTyped() {
        #expect(input.handle(key(1, "s", typed: "S")) == .edited("S"))
    }

    /// The Spanish accent key is a dead key without any modifier: it must not
    /// add "´" to the query, or "canción" would never match.
    @Test mutating func deadKeysWithoutOptionTypeNothing() {
        #expect(input.handle(key(39, "´", typed: "")) == .ignored)
        #expect(input.handle(key(31, "o", typed: "ó")) == .edited("ó"))
    }

    @Test mutating func optionDeadKeysTypeNothing() {
        // ⌥e on a US layout starts an accent and produces no character yet.
        #expect(input.handle(key(14, "e", typed: "", option: true)) == .ignored)
        #expect(input.query == "")
    }

    @Test mutating func optionWithCommandOrControlIsStillAShortcut() {
        #expect(input.handle(key(19, "2", typed: "@", command: true, option: true)) == .ignored)
        #expect(input.handle(key(19, "2", typed: "@", option: true, control: true)) == .ignored)
        #expect(input.query == "")
    }

    @Test mutating func shortcutsWithCommandOrControlAreIgnored() {
        #expect(input.handle(key(9, "v", command: true)) == .ignored)
        #expect(input.handle(key(1, "s", control: true)) == .ignored)
        #expect(input.query == "")
    }

    @Test mutating func keysWithoutPrintableTextAreIgnored() {
        #expect(input.handle(key(123, "\u{F702}")) == .ignored, "left arrow")
        #expect(input.handle(key(0)) == .ignored)
    }

    @Test mutating func deleteRemovesTheLastCharacter() {
        _ = input.handle(key(1, "é"))
        _ = input.handle(key(1, "👋"))
        #expect(input.handle(key(51)) == .edited("é"))
        #expect(input.handle(key(51)) == .edited(""))
        #expect(input.handle(key(51)) == .ignored, "nothing left to delete")
    }

    @Test mutating func tabAndShiftTabMoveTheSelection() {
        #expect(input.handle(key(48, "\t")) == .next)
        #expect(input.handle(key(48, "\t", shift: true)) == .previous)
    }

    @Test(arguments: [
        (false, false, false, HintAction.press), (true, false, false, .rightClick),
        (false, true, false, .doubleClick), (false, false, true, .moveCursor),
    ])
    func returnJumpsWithTheHintModifiers(shift: Bool, command: Bool, option: Bool, action: HintAction) {
        var input = SearchInput()
        for keyCode: UInt16 in [36, 76] {
            #expect(input.handle(key(keyCode, "\r", shift: shift, command: command, option: option)) == .jump(action))
        }
    }

    @Test mutating func escapeCancels() {
        _ = input.handle(key(1, "s"))
        #expect(input.handle(key(53)) == .cancel)
    }
}
