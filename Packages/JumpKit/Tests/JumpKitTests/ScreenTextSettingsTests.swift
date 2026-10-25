import Foundation
import Testing
@testable import JumpKit

@Suite("Screen text recognition setting")
struct ScreenTextSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ScreenTextSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func isOffByDefault() {
        #expect(JumpSettings(defaults: freshDefaults()).recognizesScreenText == false)
    }

    @Test func persistsAcrossLaunches() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)

        settings.setRecognizesScreenText(true)

        #expect(settings.recognizesScreenText)
        #expect(JumpSettings(defaults: defaults).recognizesScreenText)

        settings.setRecognizesScreenText(false)
        #expect(JumpSettings(defaults: defaults).recognizesScreenText == false)
    }

    @Test func anInvalidStoredValueFallsBackToOff() {
        let defaults = freshDefaults()
        defaults.set("sure", forKey: "recognizeScreenText")

        #expect(JumpSettings(defaults: defaults).recognizesScreenText == false)
    }
}
