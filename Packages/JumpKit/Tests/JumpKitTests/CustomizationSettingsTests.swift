import AppKit
import Foundation
import Testing
@testable import JumpKit

@Suite("Scroll and label customization")
struct CustomizationSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "CustomizationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsKeepTodaysBehavior() {
        let settings = JumpSettings(defaults: freshDefaults())
        #expect(settings.scrollSpeed == .normal)
        #expect(settings.showsScrollOutline)
        #expect(settings.hintAppearance.labelCase == .upper)
    }

    @Test func choicesPersistAcrossLaunches() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)

        settings.setScrollSpeed(.fast)
        settings.setShowsScrollOutline(false)
        settings.setHintLabelCase(.lower)

        let relaunched = JumpSettings(defaults: defaults)
        #expect(relaunched.scrollSpeed == .fast)
        #expect(relaunched.showsScrollOutline == false)
        #expect(relaunched.hintAppearance.labelCase == .lower)
    }

    @Test func invalidStoredValuesFallBackToTheDefaults() {
        let defaults = freshDefaults()
        defaults.set("warp", forKey: "scrollSpeed")
        defaults.set("maybe", forKey: "scrollOutline")
        defaults.set("title", forKey: "hintLabelCase")

        let settings = JumpSettings(defaults: defaults)
        #expect(settings.scrollSpeed == .normal)
        #expect(settings.showsScrollOutline)
        #expect(settings.hintAppearance.labelCase == .upper)
    }

    @Test func otherAppearanceChoicesAreUnaffected() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)
        settings.setHintTheme(.classic)
        settings.setHintSize(15)

        settings.setHintLabelCase(.lower)

        let relaunched = JumpSettings(defaults: defaults)
        #expect(relaunched.hintAppearance == HintAppearance(theme: .classic, size: 15, glass: .off, labelCase: .lower))
    }

    @Test func normalSpeedKeepsTheOriginalStepAndTheOthersHalveOrDoubleIt() {
        #expect(ScrollSpeed.normal.pixelsPerTick == ScrollMetrics.smoothStep)
        #expect(ScrollSpeed.slow.pixelsPerTick == ScrollMetrics.smoothStep / 2)
        #expect(ScrollSpeed.fast.pixelsPerTick == ScrollMetrics.smoothStep * 2)
    }

    @Test func lowercaseLabelsOnlyChangeWhatIsDrawn() {
        let palette = HintTheme.dark.palette(isDark: true, accent: .systemBlue)
        let upper = HintsView.Metrics(appearance: .standard)
        var lowerAppearance = HintAppearance.standard
        lowerAppearance.labelCase = .lower
        let lower = HintsView.Metrics(appearance: lowerAppearance)

        #expect(upper.label("JU", typed: "J", palette: palette).string == "JU")
        let drawn = lower.label("JU", typed: "J", palette: palette)
        #expect(drawn.string == "ju")
        // The typed prefix stays highlighted.
        #expect(drawn.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == palette.typed)
        #expect(drawn.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor == palette.text)
    }

    @Test func aHiddenOutlineDrawsNothingButTheAreaIsStillPlaced() {
        let panel = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let area = CGRect(x: 100, y: 100, width: 200, height: 200)
        #expect(HintOverlay.outline(area, in: panel, shown: true) == area)
        #expect(HintOverlay.outline(area, in: panel, shown: false) == nil)
        #expect(HintOverlay.outline(area, in: CGRect(x: 2000, y: 0, width: 10, height: 10), shown: true) == nil)
    }
}
