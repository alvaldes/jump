import AppKit
import Testing
@testable import JumpKit

@Suite("Search overlay layout")
struct SearchLayoutTests {
    /// Primary screen 1000×800 at the origin, a second 800×600 screen to its right.
    static let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
    static let secondary = CGRect(x: 1000, y: 0, width: 800, height: 600)

    private func presentation(matches: [CGRect], selected: Int? = nil,
                              window: CGRect = CGRect(x: 100, y: 50, width: 600, height: 400)) -> SearchPresentation {
        SearchPresentation(query: "jump", status: selected.map { .matches(selected: $0) } ?? .noMatches,
                           matches: matches, windowFrame: window)
    }

    @Test func matchesAreConvertedToPanelCoordinates() {
        let search = SearchLayout.search(for: presentation(matches: [CGRect(x: 200, y: 100, width: 40, height: 16)]),
                                         panelFrame: Self.primary, primaryScreenHeight: 800, showsBox: true)
        // AX top-left y 100 with height 16 → AppKit y 800 - 116.
        #expect(search.highlights == [.init(frame: CGRect(x: 200, y: 684, width: 40, height: 16), isSelected: false)])
        #expect(search.windowFrame == CGRect(x: 100, y: 350, width: 600, height: 400))
    }

    @Test func highlightsOnlyReachThePanelTheyIntersect() {
        let matches = [CGRect(x: 200, y: 100, width: 40, height: 16), CGRect(x: 1200, y: 300, width: 50, height: 20)]
        let p = presentation(matches: matches, selected: 1)
        let onPrimary = SearchLayout.search(for: p, panelFrame: Self.primary, primaryScreenHeight: 800, showsBox: true)
        let onSecondary = SearchLayout.search(for: p, panelFrame: Self.secondary, primaryScreenHeight: 800, showsBox: false)

        #expect(onPrimary.highlights == [.init(frame: CGRect(x: 200, y: 684, width: 40, height: 16), isSelected: false)])
        // Offset by the panel origin; the selected match keeps its selection on its panel.
        #expect(onSecondary.highlights == [.init(frame: CGRect(x: 200, y: 480, width: 50, height: 20), isSelected: true)])
        #expect(onSecondary.windowFrame == nil)
        #expect(onPrimary.matchCount == 2 && onSecondary.matchCount == 2)
    }

    @Test func theBoxGoesToThePanelHoldingTheWindowTopCenter() {
        let frames = [Self.primary, Self.secondary]
        #expect(SearchLayout.boxPanelIndex(for: CGRect(x: 100, y: 50, width: 600, height: 400),
                                           panelFrames: frames, primaryScreenHeight: 800) == 0)
        // Mostly on the primary screen, but its top center is on the second one.
        #expect(SearchLayout.boxPanelIndex(for: CGRect(x: 500, y: 300, width: 1100, height: 200),
                                           panelFrames: frames, primaryScreenHeight: 800) == 1)
        // Top edge above every screen: falls back to a panel the window intersects.
        #expect(SearchLayout.boxPanelIndex(for: CGRect(x: 1100, y: -100, width: 400, height: 400),
                                           panelFrames: frames, primaryScreenHeight: 800) == 1)
    }

    @Test func statusTextFollowsTheStatus() {
        #expect(SearchLayout.statusText(.collecting, matchCount: 0) == "Searching…")
        #expect(SearchLayout.statusText(.noMatches, matchCount: 0) == "No matches")
        #expect(SearchLayout.statusText(.matches(selected: 2), matchCount: 5) == "3 of 5")
        #expect(SearchLayout.statusText(.idle, matchCount: 0) == nil)
    }
}

@Suite("Search overlay drawing")
struct SearchDrawingTests {
    private func makeView(theme: HintTheme = .dark, size: CGFloat = 11, glass: HintGlass = .off) -> HintsView {
        let view = HintsView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.hintAppearance = HintAppearance(theme: theme, size: size, glass: glass)
        return view
    }

    private func search(query: String = "jump", status: SearchPresentation.Status = .noMatches,
                        highlights: [HintsView.Search.Highlight] = [], matchCount: Int = 0,
                        window: CGRect? = CGRect(x: 100, y: 100, width: 600, height: 500)) -> HintsView.Search {
        HintsView.Search(query: query, status: status, matchCount: matchCount, highlights: highlights, windowFrame: window)
    }

    @Test func theBoxSitsAtTheTopCenterOfTheWindow() throws {
        let view = makeView()
        view.search = search()
        let box = try #require(view.searchBoxShape())
        #expect(abs(box.frame.midX - 400) < 1)
        // Inside the window, a small margin below its top edge (AppKit y grows upward).
        #expect(box.frame.maxY < 600 && box.frame.maxY > 580)
        #expect(box.frame.minX > 100 && box.frame.maxX < 700)
    }

    @Test func theBoxIsClampedToThePanel() throws {
        let view = makeView()
        view.search = search(window: CGRect(x: -500, y: 600, width: 600, height: 500))
        let box = try #require(view.searchBoxShape())
        #expect(box.frame.minX >= 0)
        #expect(box.frame.maxY <= 800)
    }

    @Test func theBoxIsOnlyOnThePanelThatHoldsIt() {
        let view = makeView()
        view.search = search(window: nil)
        #expect(view.searchBoxShape() == nil)
    }

    @Test func theBoxGrowsWithTheQueryAndTheHintSize() throws {
        let view = makeView()
        view.search = search(query: "a")
        let short = try #require(view.searchBoxShape())
        view.search = search(query: String(repeating: "visible text ", count: 6))
        let long = try #require(view.searchBoxShape())
        #expect(long.frame.width > short.frame.width)

        let large = makeView(size: 20)
        large.search = search(query: "a")
        let largeBox = try #require(large.searchBoxShape())
        #expect(largeBox.frame.height > short.frame.height)
        #expect(largeBox.query.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            == NSFont.systemFont(ofSize: 20 + SearchLayout.boxFontIncrease))
    }

    @Test(arguments: [
        (SearchPresentation.Status.collecting, 0, "Searching…"),
        (.noMatches, 0, "No matches"),
        (.matches(selected: 0), 4, "1 of 4"),
    ])
    func theBoxShowsTheStatus(status: SearchPresentation.Status, count: Int, text: String) throws {
        let view = makeView()
        view.search = search(status: status, matchCount: count)
        #expect(try #require(view.searchBoxShape()).status?.string == text)
    }

    @Test func idleShowsNoStatus() throws {
        let view = makeView()
        view.search = search(query: "", status: .idle)
        #expect(try #require(view.searchBoxShape()).status == nil)
    }

    @Test(arguments: HintTheme.allCases)
    func theBoxUsesTheThemeAndAPlaceholderWhenEmpty(theme: HintTheme) throws {
        let view = makeView(theme: theme)
        let palette = view.palette
        view.search = search(query: "", status: .idle)
        let empty = try #require(view.searchBoxShape())
        #expect(empty.query.string == "Search visible text")
        #expect(empty.query.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == palette.typed)
        #expect(empty.fill == palette.fill && empty.border == palette.border)

        view.search = search(query: "jump", status: .noMatches)
        let typed = try #require(view.searchBoxShape())
        #expect(typed.query.string == "jump")
        #expect(typed.query.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == palette.text)
        #expect(typed.status?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == palette.text)
    }

    @Test(arguments: HintTheme.allCases)
    func theSelectedMatchStandsOut(theme: HintTheme) throws {
        let view = makeView(theme: theme)
        let palette = view.palette
        let frames = [CGRect(x: 10, y: 10, width: 40, height: 16), CGRect(x: 100, y: 10, width: 40, height: 16),
                      CGRect(x: 200, y: 10, width: 40, height: 16)]
        view.search = search(status: .matches(selected: 1),
                             highlights: frames.enumerated().map { .init(frame: $1, isSelected: $0 == 1) }, matchCount: 3)
        let shapes = view.searchHighlightShapes()
        #expect(shapes.count == 3)
        // Every match is highlighted, slightly outset; the selected one is drawn last (on top).
        #expect(shapes.map(\.frame).sorted { $0.minX < $1.minX }
            == frames.map { $0.insetBy(dx: -SearchLayout.highlightOutset, dy: -SearchLayout.highlightOutset) })
        let selected = try #require(shapes.last)
        #expect(selected.isSelected && shapes.dropLast().allSatisfy { !$0.isSelected })
        #expect(selected.frame.contains(frames[1]))
        for other in shapes.dropLast() {
            #expect(other.stroke == palette.border && other.halo == nil)
            #expect(selected.lineWidth > other.lineWidth)
        }
        // The text color contrasts with the theme fill, which rings it as a halo.
        #expect(selected.stroke == palette.text && selected.halo == palette.fill)
        #expect(palette.textContrast >= HintTheme.minimumContrast)
    }

    @Test func liquidGlassKeepsTheBoxDrawn() {
        let view = makeView(glass: .regular)
        view.search = search()
        view.layoutSubtreeIfNeeded()
        #expect(view.searchBoxShape() != nil)
        #expect(view.subviews.isEmpty)
    }

    @Test func withoutSearchHintsRenderAsBefore() throws {
        func hints(_ view: HintsView) -> HintsView {
            view.items = [HintsView.Item(label: "JU", anchor: HintAnchor(point: CGPoint(x: 100, y: 100), alignment: .center),
                                         elementFrame: CGRect(x: 80, y: 90, width: 40, height: 20))]
            return view
        }
        func pixels(_ view: HintsView) throws -> Data {
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return try #require(bitmap.tiffRepresentation)
        }
        let plain = hints(makeView())
        let searched = hints(makeView())
        searched.search = search(highlights: [.init(frame: CGRect(x: 300, y: 300, width: 40, height: 16), isSelected: true)])
        #expect(try pixels(searched) != pixels(plain))
        searched.search = nil
        #expect(searched.searchBoxShape() == nil && searched.searchHighlightShapes().isEmpty)
        #expect(try pixels(searched) == pixels(plain))
    }
}

@Suite("Search overlay panels")
struct SearchOverlayPanelTests {
    @Test func searchReplacesHintsAndHideClearsIt() throws {
        let overlay = HintOverlay()
        overlay.syncPanels(withFrames: [SearchLayoutTests.primary, SearchLayoutTests.secondary])
        let views = overlay.panelViews
        views[0].items = [HintsView.Item(label: "A", anchor: HintAnchor(point: .zero, alignment: .center), elementFrame: .zero)]
        views[1].outline = CGRect(x: 0, y: 0, width: 10, height: 10)

        let presentation = SearchPresentation(query: "jump", status: .matches(selected: 0),
                                              matches: [CGRect(x: 1200, y: 300, width: 50, height: 20)],
                                              windowFrame: CGRect(x: 100, y: 50, width: 600, height: 400))
        let boxPanel = overlay.applySearch(presentation, primaryScreenHeight: 800)
        #expect(boxPanel == 0)
        #expect(views.allSatisfy { $0.items.isEmpty && $0.outline == nil })
        #expect(views[0].search?.windowFrame != nil && views[0].search?.highlights.isEmpty == true)
        #expect(views[1].search?.windowFrame == nil && views[1].search?.highlights.count == 1)

        overlay.hide()
        #expect(views.allSatisfy { $0.search == nil })
        #expect(!overlay.isVisible)
    }
}
