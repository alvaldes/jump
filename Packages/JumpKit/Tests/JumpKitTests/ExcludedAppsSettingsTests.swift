import Foundation
import Testing
@testable import JumpKit

@Suite("Apps where JUMP stays off")
struct ExcludedAppsSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ExcludedAppsSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func noAppIsExcludedByDefault() {
        let settings = JumpSettings(defaults: freshDefaults())

        #expect(settings.excludedApps.isEmpty)
        #expect(settings.isExcluded(bundleIdentifier: "com.apple.Terminal") == false)
    }

    @Test func anExcludedAppPersistsAcrossLaunches() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)

        settings.excludeApp("com.apple.Terminal")

        #expect(settings.excludedApps == ["com.apple.Terminal"])
        #expect(settings.isExcluded(bundleIdentifier: "com.apple.Terminal"))
        #expect(settings.isExcluded(bundleIdentifier: "com.apple.Safari") == false)
        #expect(JumpSettings(defaults: defaults).excludedApps == ["com.apple.Terminal"])
    }

    @Test func excludingTheSameAppTwiceKeepsOneEntry() {
        let settings = JumpSettings(defaults: freshDefaults())

        settings.excludeApp("com.apple.Terminal")
        settings.excludeApp("com.apple.Terminal")

        #expect(settings.excludedApps == ["com.apple.Terminal"])
    }

    @Test func includingAnAppAgainRemovesItEverywhere() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)
        settings.excludeApp("com.apple.Terminal")
        settings.excludeApp("com.apple.Safari")

        settings.includeApp("com.apple.Terminal")

        #expect(settings.excludedApps == ["com.apple.Safari"])
        #expect(settings.isExcluded(bundleIdentifier: "com.apple.Terminal") == false)
        #expect(JumpSettings(defaults: defaults).excludedApps == ["com.apple.Safari"])
    }

    @Test func anAppWithoutBundleIdentifierIsNeverExcluded() {
        let settings = JumpSettings(defaults: freshDefaults())
        settings.excludeApp("")

        #expect(settings.excludedApps.isEmpty)
        #expect(settings.isExcluded(bundleIdentifier: nil) == false)
    }

    @Test func anInvalidStoredValueFallsBackToNoApps() {
        let defaults = freshDefaults()
        defaults.set("com.apple.Terminal", forKey: "excludedApps")

        #expect(JumpSettings(defaults: defaults).excludedApps.isEmpty)
    }
}
