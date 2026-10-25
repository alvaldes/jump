import AppKit

/// Draws every hint of one screen in a single pass (no view per hint),
/// so hundreds of hints stay cheap to show.
final class HintsView: NSView {
    struct Item: Equatable {
        let label: String
        /// Anchor in this view's coordinates (bottom-left origin).
        let anchor: HintAnchor
        /// Element frame in this view's coordinates, used to slide colliding hints.
        let elementFrame: CGRect
    }

    var items: [Item] = [] {
        didSet { if items != oldValue { rotation = 0; needsDisplay = true } }
    }

    /// Already typed prefix: other hints are hidden and these characters dimmed.
    var typed = "" {
        didSet { if typed != oldValue { needsDisplay = true } }
    }

    /// Area outlined in scroll mode, in this view's coordinates.
    var outline: CGRect? {
        didSet { if outline != oldValue { needsDisplay = true } }
    }

    var hintAppearance = HintAppearance.standard {
        didSet {
            guard hintAppearance != oldValue else { return }
            metrics = Metrics(appearance: hintAppearance)
            needsDisplay = true
        }
    }

    private var metrics = Metrics(appearance: .standard)

    /// Changes which of the overlapping hints gets its preferred place.
    private var rotation = 0

    func rotate() {
        rotation += 1
        needsDisplay = true
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
        var visible = items.filter { $0.label.hasPrefix(typed) }
        guard !visible.isEmpty else { return }
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

        for (text, rect) in zip(texts, rects) {
            // Whole points (plus half for the 1 pt stroke) keep edges crisp.
            let pill = CGRect(origin: CGPoint(x: rect.minX.rounded() + 0.5, y: rect.minY.rounded() + 0.5), size: rect.size)
            guard pill.intersects(dirtyRect) else { continue }
            drawPill(pill, text: text, palette: palette)
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

    private func drawPill(_ pill: CGRect, text: NSAttributedString, palette: HintPalette) {
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        NSGraphicsContext.saveGraphicsState()
        Style.shadow.set()
        palette.fill.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        palette.border.setStroke()
        path.lineWidth = 1
        path.stroke()

        text.draw(at: CGPoint(x: pill.minX + metrics.horizontalPadding, y: pill.minY + metrics.verticalPadding))
    }
}
