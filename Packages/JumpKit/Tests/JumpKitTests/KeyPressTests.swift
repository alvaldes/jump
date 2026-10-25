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

    @Test func modifiersOtherThanShiftMarkAShortcut() {
        #expect(KeyPress(keyCode: 38, characters: "j", command: true).isShortcut)
        #expect(KeyPress(keyCode: 38, characters: "j", control: true).isShortcut)
        #expect(KeyPress(keyCode: 38, characters: "j", option: true).isShortcut)
        #expect(!KeyPress(keyCode: 38, characters: "j", shift: true).isShortcut)
    }
}
