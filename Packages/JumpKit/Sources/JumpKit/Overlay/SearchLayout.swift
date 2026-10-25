import AppKit

/// Geometry and text of the text search overlay, kept out of the views so it
/// can be tested without windows.
enum SearchLayout {
    /// How much a highlight extends past the matched text.
    static let highlightOutset: CGFloat = 2
    /// The search box font is this much larger than the hint labels.
    static let boxFontIncrease: CGFloat = 3

    /// The search drawing of one panel: AX frames converted to the panel's
    /// coordinates, keeping only the matches that intersect it.
    static func search(for presentation: SearchPresentation, panelFrame: CGRect,
                       primaryScreenHeight: CGFloat, showsBox: Bool) -> HintsView.Search {
        func local(_ frame: CGRect) -> CGRect {
            ScreenGeometry.appKitRect(fromAX: frame, primaryScreenHeight: primaryScreenHeight)
                .offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
        }
        var selected: Int?
        if case .matches(let index) = presentation.status { selected = index }
        let panelBounds = CGRect(origin: .zero, size: panelFrame.size)
        let highlights = presentation.matches.enumerated().compactMap { index, frame -> HintsView.Search.Highlight? in
            let frame = local(frame)
            guard frame.intersects(panelBounds) else { return nil }
            return HintsView.Search.Highlight(frame: frame, isSelected: index == selected)
        }
        return HintsView.Search(
            query: presentation.query,
            status: presentation.status,
            matchCount: presentation.matches.count,
            highlights: highlights,
            windowFrame: showsBox ? local(presentation.windowFrame) : nil
        )
    }

    /// The panel that shows the search box: the one holding the window's top
    /// center, else one the window intersects.
    static func boxPanelIndex(for windowFrame: CGRect, panelFrames: [CGRect], primaryScreenHeight: CGFloat) -> Int? {
        let window = ScreenGeometry.appKitRect(fromAX: windowFrame, primaryScreenHeight: primaryScreenHeight)
        // Just inside the top edge, where the box goes.
        let topCenter = CGPoint(x: window.midX, y: window.maxY - 1)
        return panelFrames.firstIndex { $0.contains(topCenter) }
            ?? panelFrames.firstIndex { $0.intersects(window) }
            ?? (panelFrames.isEmpty ? nil : 0)
    }

    static func statusText(_ status: SearchPresentation.Status, matchCount: Int) -> String? {
        switch status {
        case .collecting: "Searching…"
        case .idle: nil
        case .noMatches: "No matches"
        case .matches(let selected): "\(selected + 1) of \(matchCount)"
        }
    }
}
