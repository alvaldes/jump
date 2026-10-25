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

    /// The repository root, from this file's location.
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func everyMenuBarIconIsInTheAppsAssetCatalog() {
        let catalog = Self.repository.appending(path: "JUMP/Resources/Assets.xcassets")
        for icon in MenuBarIcon.allCases {
            let imageset = catalog.appending(path: "\(icon.imageName).imageset")
            #expect(FileManager.default.fileExists(atPath: imageset.path), "\(icon)")
        }
    }

    @Test func theGlyphIconIsCompiledAsAnAlternateAppIcon() throws {
        let name = try #require(AppIconChoice.glyph.imageName)
        let bundle = Self.repository.appending(path: "JUMP/Resources/\(name).icon")
        #expect(FileManager.default.fileExists(atPath: bundle.path))
        let project = try String(contentsOf: Self.repository.appending(path: "project.yml"), encoding: .utf8)
        #expect(project.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: \(name)"))
        #expect(AppIconChoice.official.imageName == nil)
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
