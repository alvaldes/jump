import Foundation
import Testing
@testable import JumpKit

@Suite("Modifier for each action")
struct ActionModifiersTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ActionModifiersTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func press(shift: Bool = false, command: Bool = false, option: Bool = false, control: Bool = false) -> KeyPress {
        KeyPress(keyCode: 0, characters: "a", shift: shift, command: command, option: option, control: control)
    }

    @Test func standardMappingKeepsTheOriginalModifiers() {
        let standard = ActionModifiers.standard
        #expect(standard.action(for: press()) == .press)
        #expect(standard.action(for: press(shift: true)) == .rightClick)
        #expect(standard.action(for: press(command: true)) == .doubleClick)
        #expect(standard.action(for: press(option: true)) == .moveCursor)
        #expect(standard.action(for: press(control: true)) == .press, "Control is unused by default")
    }

    @Test func withSeveralModifiersHeldTheFirstActionWins() {
        #expect(ActionModifiers.standard.action(for: press(shift: true, command: true, option: true)) == .rightClick)
        #expect(ActionModifiers.standard.action(for: press(command: true, option: true)) == .doubleClick)
    }

    @Test func aCustomMappingChoosesTheAction() {
        var modifiers = ActionModifiers.standard
        modifiers.assign(.control, to: .rightClick)

        #expect(modifiers.action(for: press(control: true)) == .rightClick)
        #expect(modifiers.action(for: press(shift: true)) == .press, "Shift is free now")
    }

    @Test func assigningAModifierInUseSwapsThem() {
        var modifiers = ActionModifiers.standard
        modifiers.assign(.command, to: .rightClick)

        #expect(modifiers.modifier(for: .rightClick) == .command)
        #expect(modifiers.modifier(for: .doubleClick) == .shift)
        #expect(modifiers.modifier(for: .moveCursor) == .option)
    }

    @Test func theMappingPersistsAcrossLaunches() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)
        #expect(settings.actionModifiers == .standard)

        settings.setActionModifier(.option, for: .doubleClick)

        let expected = ActionModifiers(rightClick: .shift, doubleClick: .option, moveCursor: .command)
        #expect(settings.actionModifiers == expected)
        #expect(JumpSettings(defaults: defaults).actionModifiers == expected)
    }

    @Test func aStoredMappingThatRepeatsAModifierFallsBackToTheStandardOne() {
        let defaults = freshDefaults()
        defaults.set("shift", forKey: "rightClickModifier")
        defaults.set("shift", forKey: "doubleClickModifier")
        defaults.set("option", forKey: "moveCursorModifier")

        #expect(JumpSettings(defaults: defaults).actionModifiers == .standard)
    }

    @Test func anInvalidStoredModifierFallsBackToTheStandardOne() {
        let defaults = freshDefaults()
        defaults.set("hyper", forKey: "rightClickModifier")

        #expect(JumpSettings(defaults: defaults).actionModifiers == .standard)
    }

    @Test func returnInTextSearchUsesTheCustomMapping() {
        var modifiers = ActionModifiers.standard
        modifiers.assign(.control, to: .moveCursor)
        var input = SearchInput()

        let result = input.handle(KeyPress(keyCode: 36, characters: "\r", control: true), modifiers: modifiers)

        #expect(result == .jump(.moveCursor))
    }
}
