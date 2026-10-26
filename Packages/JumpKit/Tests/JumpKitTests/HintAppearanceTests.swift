import AppKit
import Testing
@testable import JumpKit

@Suite("Hint appearance")
struct HintAppearanceTests {
    /// The colors macOS offers as accent color (graphite is gray).
    static let accents: [NSColor] = [
        .systemBlue, .systemPurple, .systemPink, .systemRed, .systemOrange,
        .systemYellow, .systemGreen, .systemGray,
    ]

    @Test(arguments: HintTheme.allCases, [false, true])
    func everyThemeKeepsLabelsReadable(theme: HintTheme, isDark: Bool) {
        for accent in Self.accents {
            let palette = theme.palette(isDark: isDark, accent: accent)
            #expect(palette.textContrast >= 4.5, "\(theme) dark=\(isDark) accent=\(accent)")
        }
    }

    @Test func darkIsTheDefaultAndKeepsTheOriginalLook() {
        #expect(HintAppearance.standard == HintAppearance(theme: .dark, size: 11, glass: .off))
        let palette = HintTheme.dark.palette(isDark: false, accent: .systemBlue)
        #expect(palette.fill == NSColor(white: 0.08, alpha: 0.9))
        #expect(palette.text == .white)
        #expect(palette.typed == NSColor(white: 1, alpha: 0.4))
        #expect(palette.border == NSColor(white: 1, alpha: 0.18))
    }

    @Test func systemFollowsTheAppearance() {
        #expect(HintTheme.system.palette(isDark: true, accent: .systemBlue)
            == HintTheme.dark.palette(isDark: true, accent: .systemBlue))
        #expect(HintTheme.system.palette(isDark: false, accent: .systemBlue)
            == HintTheme.light.palette(isDark: false, accent: .systemBlue))
    }

    @Test func accentPicksTheMoreReadableText() {
        #expect(HintTheme.accent.palette(isDark: false, accent: .systemBlue).text == .white)
        #expect(HintTheme.accent.palette(isDark: false, accent: .systemYellow).text == .black)
    }

    @Test func pillsScaleWithTheSize() {
        let small = HintsView.Metrics(appearance: HintAppearance(theme: .dark, size: 11, glass: .off))
        let large = HintsView.Metrics(appearance: HintAppearance(theme: .dark, size: 22, glass: .off))
        let smallPill = small.pillSize(for: small.label("JU", typed: "", palette: HintTheme.dark.palette(isDark: true, accent: .systemBlue)))
        let largePill = large.pillSize(for: large.label("JU", typed: "", palette: HintTheme.dark.palette(isDark: true, accent: .systemBlue)))
        #expect(large.font.pointSize == 22)
        #expect(largePill.height > smallPill.height * 1.8)
        #expect(largePill.width > smallPill.width * 1.8)
    }

    @Test func theDefaultSizeKeepsTheOriginalMetrics() {
        let metrics = HintsView.Metrics(appearance: .standard)
        #expect(metrics.font == NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold))
        #expect(metrics.horizontalPadding == 6)
        #expect(metrics.verticalPadding == 2.5)
        #expect(metrics.kerning == 0.6)
    }
}

@Suite("JumpSettings appearance")
struct JumpSettingsAppearanceTests {
    private func freshDefaults() -> UserDefaults {
        let name = "JumpSettingsAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToTheStandardAppearance() {
        #expect(JumpSettings(defaults: freshDefaults()).hintAppearance == .standard)
    }

    @Test func choicesPersistAcrossLaunches() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)

        settings.setHintTheme(.classic)
        settings.setHintSize(15)
        settings.setHintGlass(.clear)

        let expected = HintAppearance(theme: .classic, size: 15, glass: .clear)
        #expect(settings.hintAppearance == expected)
        #expect(JumpSettings(defaults: defaults).hintAppearance == expected)
    }

    @Test func sizesAreRoundedAndKeptInRange() {
        let settings = JumpSettings(defaults: freshDefaults())

        settings.setHintSize(14.6)
        #expect(settings.hintAppearance.size == 15)
        settings.setHintSize(2)
        #expect(settings.hintAppearance.size == HintAppearance.sizeRange.lowerBound)
        settings.setHintSize(400)
        #expect(settings.hintAppearance.size == HintAppearance.sizeRange.upperBound)
    }

    @Test func sizesGoDownToSevenPoints() {
        let settings = JumpSettings(defaults: freshDefaults())

        settings.setHintSize(7)
        #expect(settings.hintAppearance.size == 7)
        settings.setHintSize(6)
        #expect(settings.hintAppearance.size == 7)
        #expect(HintAppearance.sizeRange == 7...20)
    }

    @Test func storedSizesAreRoundedOnLoad() {
        let defaults = freshDefaults()
        defaults.set(14.6, forKey: "hintSize")
        #expect(JumpSettings(defaults: defaults).hintAppearance.size == 15)
    }

    @Test func invalidStoredValuesFallBackToTheDefaults() {
        let defaults = freshDefaults()
        defaults.set("neon", forKey: "hintTheme")
        defaults.set(400.0, forKey: "hintSize")
        defaults.set("yes", forKey: "hintGlass")

        #expect(JumpSettings(defaults: defaults).hintAppearance == .standard)
    }

    @Test func hintCharactersAreUnaffected() {
        let defaults = freshDefaults()
        let settings = JumpSettings(defaults: defaults)
        #expect(settings.setHintCharacters("asdf"))

        settings.setHintTheme(.light)
        settings.setHintSize(13)

        #expect(JumpSettings(defaults: defaults).hintCharacters == "asdf")
    }
}

@Suite("Liquid Glass hints")
struct GlassHintsTests {
    private func makeView(glass: HintGlass) -> HintsView {
        let view = HintsView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.hintAppearance = HintAppearance(theme: .dark, size: 11, glass: glass)
        view.items = ["sa", "sd", "f"].enumerated().map { index, label in
            let point = CGPoint(x: 60 + index * 100, y: 150)
            return HintsView.Item(label: label, anchor: HintAnchor(point: point, alignment: .center),
                                  elementFrame: CGRect(x: point.x - 20, y: point.y - 10, width: 40, height: 20))
        }
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func visibleGlass(in view: HintsView) -> [NSGlassEffectView] {
        view.subviews.compactMap { $0 as? NSGlassEffectView }.filter { !$0.isHidden }
    }

    @Test func eachVisibleHintGetsAGlassPill() {
        let view = makeView(glass: .regular)
        let glass = visibleGlass(in: view)
        #expect(glass.count == 3)
        #expect(glass.allSatisfy { $0.cornerRadius == $0.frame.height / 2 && $0.contentView != nil })
    }

    @Test func typingHidesTheGlassOfOtherHints() {
        let view = makeView(glass: .regular)
        view.typed = "s"
        view.layoutSubtreeIfNeeded()
        #expect(visibleGlass(in: view).count == 2)
    }

    @Test func glassViewsAreReused() {
        let view = makeView(glass: .regular)
        let first = Set(view.subviews.map(ObjectIdentifier.init))
        view.typed = "s"
        view.layoutSubtreeIfNeeded()
        view.typed = ""
        view.layoutSubtreeIfNeeded()
        #expect(Set(view.subviews.map(ObjectIdentifier.init)) == first)
    }

    @Test func turningGlassOffHidesEveryGlassPill() {
        let view = makeView(glass: .regular)
        view.hintAppearance = .standard
        view.layoutSubtreeIfNeeded()
        #expect(visibleGlass(in: view).isEmpty)
    }

    @Test func onlyColoredThemesTintTheGlass() {
        for theme in HintTheme.allCases {
            let view = makeView(glass: .regular)
            view.hintAppearance = HintAppearance(theme: theme, size: 11, glass: .regular)
            view.layoutSubtreeIfNeeded()
            let tinted = visibleGlass(in: view).map { $0.tintColor != nil }
            #expect(tinted == Array(repeating: theme == .accent || theme == .classic, count: 3), "\(theme)")
        }
    }

    @Test(arguments: [HintGlass.regular, .clear])
    func theChosenGlassStyleIsUsed(glass: HintGlass) {
        let view = makeView(glass: .regular)
        view.hintAppearance = HintAppearance(theme: .dark, size: 11, glass: glass)
        view.layoutSubtreeIfNeeded()
        let expected: NSGlassEffectView.Style = glass == .clear ? .clear : .regular
        #expect(visibleGlass(in: view).map(\.style) == Array(repeating: expected, count: 3))
    }

    @Test func withoutGlassNoGlassViewsAreCreated() {
        #expect(makeView(glass: .off).subviews.isEmpty)
    }

    @Test func hidingEveryHintHidesTheGlass() {
        let view = makeView(glass: .regular)
        view.items = []
        view.layoutSubtreeIfNeeded()
        #expect(visibleGlass(in: view).isEmpty)
    }
}
