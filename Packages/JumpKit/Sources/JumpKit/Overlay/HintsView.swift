import AppKit

/// Draws every hint of one screen in a single pass (no view per hint),
/// so hundreds of hints stay cheap to show. Liquid Glass is the exception:
/// the window server composites it, so each visible hint gets a reused
/// glass view instead.
final class HintsView: NSView {
    struct Item: Equatable {
        let label: String
        /// Anchor in this view's coordinates (bottom-left origin).
        let anchor: HintAnchor
        /// Element frame in this view's coordinates, used to slide colliding hints.
        let elementFrame: CGRect
    }

    var items: [Item] = [] {
        didSet { if items != oldValue { rotation = 0; invalidate() } }
    }

    /// Already typed prefix: other hints are hidden and these characters dimmed.
    var typed = "" {
        didSet { if typed != oldValue { invalidate() } }
    }

    /// Area outlined in scroll mode, in this view's coordinates.
    var outline: CGRect? {
        didSet { if outline != oldValue { needsDisplay = true } }
    }

    /// Text search mode: its box and highlighted matches.
    struct Search: Equatable {
        struct Highlight: Equatable {
            /// Matched text in this view's coordinates.
            let frame: CGRect
            let isSelected: Bool
        }

        var query: String
        var status: SearchPresentation.Status
        /// Matches on every screen, for "n of m".
        var matchCount: Int
        /// Matches on this screen.
        var highlights: [Highlight]
        /// Target window in this view's coordinates, when the box is on this screen.
        var windowFrame: CGRect?
    }

    var search: Search? {
        didSet { if search != oldValue { needsDisplay = true } }
    }

    var hintAppearance = HintAppearance.standard {
        didSet {
            guard hintAppearance != oldValue else { return }
            metrics = Metrics(appearance: hintAppearance)
            invalidate()
        }
    }

    /// Colors of the current theme in the overlay's appearance.
    var palette: HintPalette {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return hintAppearance.theme.palette(isDark: isDark, accent: .controlAccentColor)
    }

    private var metrics = Metrics(appearance: .standard)
    private var glassPills: [NSGlassEffectView] = []

    /// Changes which of the overlapping hints gets its preferred place.
    private var rotation = 0

    func rotate() {
        rotation += 1
        invalidate()
    }

    private func invalidate() {
        needsDisplay = true
        needsLayout = true
    }

    /// Font and spacing for one label size; the default size keeps the
    /// original 11 pt proportions.
    struct Metrics {
        let font: NSFont
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let kerning: CGFloat

        init(appearance: HintAppearance) {
            let scale = appearance.size / HintAppearance.standard.size
            font = .monospacedSystemFont(ofSize: appearance.size, weight: .semibold)
            horizontalPadding = 6 * scale
            verticalPadding = 2.5 * scale
            kerning = 0.6 * scale
        }

        func label(_ label: String, typed: String, palette: HintPalette) -> NSAttributedString {
            let text = NSMutableAttributedString(string: label, attributes: [
                .font: font,
                .foregroundColor: palette.text,
                .kern: kerning,
            ])
            text.addAttribute(.foregroundColor, value: palette.typed, range: NSRange(location: 0, length: typed.utf16.count))
            return text
        }

        func pillSize(for text: NSAttributedString) -> CGSize {
            let textSize = text.size()
            return CGSize(
                width: ceil(textSize.width + horizontalPadding * 2),
                height: ceil(textSize.height + verticalPadding * 2)
            )
        }
    }

    private enum Style {
        static let shadow: NSShadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowOffset = CGSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 3
            return shadow
        }()
    }

    /// Draws one label off screen so fonts and glyph caches are loaded.
    static func warmUpTextRendering(_ appearance: HintAppearance) {
        let view = HintsView(frame: CGRect(x: 0, y: 0, width: 64, height: 32))
        view.hintAppearance = appearance
        view.items = [Item(label: "JU", anchor: HintAnchor(point: CGPoint(x: 32, y: 16), alignment: .center),
                           elementFrame: view.bounds)]
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        if search != nil {
            let palette = palette
            for highlight in searchHighlightShapes(palette: palette) where highlight.frame.intersects(dirtyRect) {
                drawHighlight(highlight)
            }
            // Drawn even with Liquid Glass on: the box holds text being typed
            // and must stay readable over anything, which a drawn pill guarantees.
            if let box = searchBoxShape(palette: palette), box.frame.intersects(dirtyRect) {
                drawSearchBox(box)
            }
        }
        if let outline {
            drawOutline(outline)
        }
        guard hintAppearance.glass == .off else { return }
        for pill in placedPills() where pill.frame.intersects(dirtyRect) {
            drawPill(pill)
        }
    }

    override func layout() {
        super.layout()
        let pills = hintAppearance.glass == .off ? [] : placedPills()
        let style: NSGlassEffectView.Style = hintAppearance.glass == .clear ? .clear : .regular
        while glassPills.count < pills.count {
            let glass = NSGlassEffectView()
            glass.contentView = GlassLabelView()
            addSubview(glass)
            glassPills.append(glass)
        }
        for (index, glass) in glassPills.enumerated() {
            guard index < pills.count else {
                if !glass.isHidden { glass.isHidden = true }
                continue
            }
            let pill = pills[index]
            // Setting a glass property re-renders the glass even when the value
            // is unchanged, so only changes are applied.
            if glass.frame != pill.frame { glass.frame = pill.frame }
            if glass.cornerRadius != pill.frame.height / 2 { glass.cornerRadius = pill.frame.height / 2 }
            if glass.style != style { glass.style = style }
            if glass.tintColor != pill.palette.glassTint { glass.tintColor = pill.palette.glassTint }
            (glass.contentView as? GlassLabelView)?.show(pill.text, at: CGPoint(x: metrics.horizontalPadding, y: metrics.verticalPadding))
            if glass.isHidden { glass.isHidden = false }
        }
    }

    private struct Pill {
        let text: NSAttributedString
        let frame: CGRect
        let palette: HintPalette
    }

    /// Visible hints with their labels and final frames.
    private func placedPills() -> [Pill] {
        var visible = items.filter { $0.label.hasPrefix(typed) }
        guard !visible.isEmpty else { return [] }
        // Earlier hints win the free spots and later ones are drawn on top, so
        // reversing the order swaps every overlapping pair.
        if rotation.isMultiple(of: 2) == false {
            visible.reverse()
        }

        let palette = palette
        let texts = visible.map { metrics.label($0.label, typed: typed, palette: palette) }
        let rects = HintLayout.place(zip(visible, texts).map { item, text in
            HintLayout.Request(size: metrics.pillSize(for: text), anchor: item.anchor, elementFrame: item.elementFrame)
        })
        return zip(texts, rects).map { text, rect in
            // Whole points (plus half for the 1 pt stroke) keep edges crisp.
            let frame = CGRect(origin: CGPoint(x: rect.minX.rounded() + 0.5, y: rect.minY.rounded() + 0.5), size: rect.size)
            return Pill(text: text, frame: frame, palette: palette)
        }
    }

    private func drawOutline(_ frame: CGRect) {
        let rect = frame.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 3
        path.stroke()
    }

    private func drawPill(_ pill: Pill) {
        let frame = pill.frame
        let path = NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2)
        NSGraphicsContext.saveGraphicsState()
        Style.shadow.set()
        pill.palette.fill.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        pill.palette.border.setStroke()
        path.lineWidth = 1
        path.stroke()

        pill.text.draw(at: CGPoint(x: frame.minX + metrics.horizontalPadding, y: frame.minY + metrics.verticalPadding))
    }
}

// MARK: - Text search

extension HintsView {
    /// One highlighted match as drawn.
    struct HighlightShape {
        let frame: CGRect
        let isSelected: Bool
        let fill: NSColor
        let stroke: NSColor
        let lineWidth: CGFloat
        /// A wider ring under the stroke, so the selected match stands out on
        /// any background.
        let halo: NSColor?
    }

    /// The search box as drawn.
    struct SearchBoxShape {
        let frame: CGRect
        let fill: NSColor
        let border: NSColor
        let query: NSAttributedString
        let queryRect: CGRect
        let status: NSAttributedString?
        let statusOrigin: CGPoint
    }

    /// Highlights in drawing order: the selected match last, on top.
    func searchHighlightShapes() -> [HighlightShape] {
        searchHighlightShapes(palette: palette)
    }

    func searchBoxShape() -> SearchBoxShape? {
        searchBoxShape(palette: palette)
    }

    fileprivate func searchHighlightShapes(palette: HintPalette) -> [HighlightShape] {
        guard let search else { return [] }
        let outset = SearchLayout.highlightOutset
        let shapes = search.highlights.map { highlight in
            HighlightShape(
                frame: highlight.frame.insetBy(dx: -outset, dy: -outset),
                isSelected: highlight.isSelected,
                fill: palette.fill.withAlphaComponent(highlight.isSelected ? 0.35 : 0.22),
                // The theme's text color contrasts with its fill, which rings it.
                stroke: highlight.isSelected ? palette.text : palette.border,
                lineWidth: highlight.isSelected ? 2 : 1,
                halo: highlight.isSelected ? palette.fill : nil
            )
        }
        return shapes.filter { !$0.isSelected } + shapes.filter(\.isSelected)
    }

    fileprivate func searchBoxShape(palette: HintPalette) -> SearchBoxShape? {
        guard let search, let window = search.windowFrame else { return nil }
        let scale = hintAppearance.size / HintAppearance.standard.size
        let horizontalPadding = 12 * scale
        let verticalPadding = 7 * scale
        let gap = 16 * scale
        let topMargin = 10 * scale
        let minimumWidth = 240 * scale
        let edgeInset: CGFloat = 4

        let fontSize = hintAppearance.size + SearchLayout.boxFontIncrease
        let truncating = NSMutableParagraphStyle()
        // While typing, the end of a long query is what matters.
        truncating.lineBreakMode = .byTruncatingHead
        let isEmpty = search.query.isEmpty
        let query = NSAttributedString(string: isEmpty ? "Search visible text" : search.query, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: isEmpty ? palette.typed : palette.text,
            .paragraphStyle: truncating,
        ])
        let status = SearchLayout.statusText(search.status, matchCount: search.matchCount).map {
            NSAttributedString(string: $0, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize - 1, weight: .medium),
                .foregroundColor: palette.text,
            ])
        }

        let querySize = query.size()
        let statusSize = status?.size() ?? .zero
        let statusSpace = status == nil ? 0 : gap + ceil(statusSize.width)
        let textHeight = ceil(max(querySize.height, statusSize.height))
        let height = textHeight + verticalPadding * 2
        let width = min(
            max(minimumWidth, ceil(querySize.width) + statusSpace + horizontalPadding * 2),
            bounds.width - edgeInset * 2
        )

        func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            max(lower, min(value, upper))
        }
        let x = clamp(window.midX - width / 2, edgeInset, bounds.width - edgeInset - width)
        let y = clamp(window.maxY - topMargin - height, edgeInset, bounds.height - edgeInset - height)
        // Whole points (plus half for the 1 pt stroke) keep edges crisp.
        let frame = CGRect(x: x.rounded() + 0.5, y: y.rounded() + 0.5, width: width, height: height)

        let textY = frame.minY + verticalPadding
        return SearchBoxShape(
            frame: frame,
            fill: palette.fill,
            border: palette.border,
            query: query,
            queryRect: CGRect(x: frame.minX + horizontalPadding, y: textY,
                              width: max(0, frame.width - horizontalPadding * 2 - statusSpace), height: textHeight),
            status: status,
            statusOrigin: CGPoint(x: frame.maxX - horizontalPadding - ceil(statusSize.width),
                                  y: textY + (textHeight - statusSize.height) / 2)
        )
    }

    fileprivate func drawHighlight(_ shape: HighlightShape) {
        let path = NSBezierPath(roundedRect: shape.frame, xRadius: 4, yRadius: 4)
        shape.fill.setFill()
        path.fill()
        if let halo = shape.halo {
            halo.setStroke()
            path.lineWidth = shape.lineWidth + 3
            path.stroke()
        }
        shape.stroke.setStroke()
        path.lineWidth = shape.lineWidth
        path.stroke()
    }

    fileprivate func drawSearchBox(_ box: SearchBoxShape) {
        let radius = min(10, box.frame.height / 2)
        let path = NSBezierPath(roundedRect: box.frame, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        Style.shadow.set()
        box.fill.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        box.border.setStroke()
        path.lineWidth = 1
        path.stroke()

        box.query.draw(with: box.queryRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        box.status?.draw(at: box.statusOrigin)
    }
}

/// The label inside a Liquid Glass pill.
private final class GlassLabelView: NSView {
    private var text = NSAttributedString()
    private var origin = CGPoint.zero

    func show(_ text: NSAttributedString, at origin: CGPoint) {
        guard text != self.text || origin != self.origin else { return }
        self.text = text
        self.origin = origin
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        text.draw(at: origin)
    }
}
