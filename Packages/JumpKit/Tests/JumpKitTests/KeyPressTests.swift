import AppKit
import Testing
@testable import JumpKit

@Suite("KeyPress decoding")
struct KeyPressTests {
    private func press(_ keyCode: UInt16, _ characters: String = "", shift: Bool = false) -> KeyPress {
        KeyPress(keyCode: keyCode, characters: characters, shift: shift)
    }

    @Test func hintModeSpecialKeys() {
        #expect(HintKey(press(53)) == .escape)
        #expect(HintKey(press(51)) == .backspace)
        #expect(HintKey(press(49, " ")) == .space)
    }

    @Test func hintModeLetters() {
        #expect(HintKey(press(1, "s")) == .character("s"))
        #expect(HintKey(press(0)) == nil, "no character, no key")
    }

    @Test func scrollModeSpecialKeys() {
        #expect(ScrollKey(press(53)) == .escape)
        #expect(ScrollKey(press(48)) == .tab)
    }

    @Test func scrollModeLettersIgnoreCapsLockButNotShift() {
        #expect(ScrollKey(press(38, "J")) == .character("j"))
        #expect(ScrollKey(press(5, "g", shift: true)) == .character("G"))
    }

    /// ⌥2 on a Spanish layout: the layout types `@`, the key itself is `2`.
    private func optionTwoEvent() throws -> KeyPress {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: 0, context: nil,
            characters: "@", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19
        ))
        return KeyPress(event)
    }

    @Test func keepsWhatTheLayoutTyped() throws {
        let press = try optionTwoEvent()
        #expect(press.typedCharacters == "@")
        #expect(press.characters == "2", "hint and scroll keys still read the key ignoring modifiers")
        #expect(press.option)
    }

    @Test func hintAndScrollKeysIgnoreWhatOptionTyped() throws {
        let press = try optionTwoEvent()
        #expect(HintKey(press) == .character("2"))
        #expect(ScrollKey(press) == ScrollKey(KeyPress(keyCode: 19, characters: "2", option: true)))
    }

    @Test func typedCharactersDefaultToTheKeyCharacters() {
        #expect(KeyPress(keyCode: 1, characters: "s").typedCharacters == "s")
    }

    @Test func modifiersOtherThanShiftMarkAShortcut() {
        #expect(KeyPress(keyCode: 38, characters: "j", command: true).isShortcut)
        #expect(KeyPress(keyCode: 38, characters: "j", control: true).isShortcut)
        #expect(KeyPress(keyCode: 38, characters: "j", option: true).isShortcut)
        #expect(!KeyPress(keyCode: 38, characters: "j", shift: true).isShortcut)
    }
}
