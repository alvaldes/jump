import Foundation
import Testing
@testable import JumpKit

@Suite("Icon settings")
struct IconSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "IconSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToTheKeycapMenuBarIconAndTheOfficialIconOutOfTheDock() {
        let settings = JumpSettings(defaults: freshDefaults())
        #expect(settings.menuBarIcon == .keycap)
        #expect(settings.showInDock == false)
        #expect(settings.appIcon == .official)
    }

    @Test func choicesPersistAcrossLaunches() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)

        settings.setMenuBarIcon(.filled)
        settings.setShowInDock(true)
        settings.setAppIcon(.glyph)

        let relaunched = JumpSettings(defaults: defaults)
        #expect(relaunched.menuBarIcon == .filled)
        #expect(relaunched.showInDock)
        #expect(relaunched.appIcon == .glyph)
    }

    @Test func invalidStoredValuesFallBackToTheDefaults() {
        let defaults = freshDefaults()
        defaults.set("rainbow", forKey: "menuBarIcon")
        defaults.set("maybe", forKey: "showInDock")
        defaults.set("neon", forKey: "appIcon")

        let settings = JumpSettings(defaults: defaults)
        #expect(settings.menuBarIcon == .keycap)
        #expect(settings.showInDock == false)
        #expect(settings.appIcon == .official)
    }

    @Test func everyMenuBarIconNamesABundledImage() {
        #expect(MenuBarIcon.allCases.map(\.imageName) == ["MenuBarIconKeycap", "MenuBarIconOutline", "MenuBarIconFilled"])
    }

    @Test func onlyTheGlyphIconNamesAnAlternateImage() {
        #expect(AppIconChoice.official.imageName == nil)
        #expect(AppIconChoice.glyph.imageName == "AppIconGlyph")
    }

    @Test func otherSettingsAreUnaffected() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)
        #expect(settings.setHintCharacters("asdf"))
        settings.setHintTheme(.light)

        settings.setMenuBarIcon(.outline)
        settings.setShowInDock(true)
        settings.setAppIcon(.glyph)

        let relaunched = JumpSettings(defaults: defaults)
        #expect(relaunched.hintCharacters == "asdf")
        #expect(relaunched.hintAppearance.theme == .light)
    }
}
