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

    var hintAppearance = HintAppearance.standard {
        didSet {
            guard hintAppearance != oldValue else { return }
            metrics = Metrics(appearance: hintAppearance)
            invalidate()
        }
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
        if let outline {
            drawOutline(outline)
        }
        guard !hintAppearance.glass else { return }
        for pill in placedPills() where pill.frame.intersects(dirtyRect) {
            drawPill(pill)
        }
    }

    override func layout() {
        super.layout()
        let pills = hintAppearance.glass ? placedPills() : []
        while glassPills.count < pills.count {
            let glass = NSGlassEffectView()
            glass.contentView = GlassLabelView()
            addSubview(glass)
            glassPills.append(glass)
        }
        for (index, glass) in glassPills.enumerated() {
            guard index < pills.count else {
                glass.isHidden = true
                continue
            }
            let pill = pills[index]
            glass.frame = pill.frame
            glass.cornerRadius = pill.frame.height / 2
            // A lighter tint than the drawn fill lets the glass show through.
            glass.tintColor = pill.palette.fill.withAlphaComponent(pill.palette.fill.alphaComponent * 0.6)
            (glass.contentView as? GlassLabelView)?.show(pill.text, at: CGPoint(x: metrics.horizontalPadding, y: metrics.verticalPadding))
            glass.isHidden = false
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

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let palette = hintAppearance.theme.palette(isDark: isDark, accent: .controlAccentColor)
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
