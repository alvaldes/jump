import Foundation
import Testing
@testable import JumpKit

@Suite("JumpSettings")
struct JumpSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "JumpSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToTheHomeRowCharacters() {
        let settings = JumpSettings(defaults: freshDefaults())
        #expect(settings.hintCharacters == HintLabels.defaultCharacters)
    }

    @Test func hintCharactersPersistAcrossLaunches() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)

        #expect(settings.setHintCharacters("asdfjkl"))

        #expect(JumpSettings(defaults: defaults).hintCharacters == "asdfjkl")
    }

    @Test func hintCharactersAreNormalized() {
        let settings = JumpSettings(defaults: freshDefaults())

        #expect(settings.setHintCharacters(" AsDf a;1 "))

        #expect(settings.hintCharacters == "asdf")
    }

    @Test func fewerThanTwoUsableCharactersAreRejected() {
        let settings = JumpSettings(defaults: freshDefaults())

        #expect(!settings.setHintCharacters("aaa;;"))

        #expect(settings.hintCharacters == HintLabels.defaultCharacters)
    }
}
