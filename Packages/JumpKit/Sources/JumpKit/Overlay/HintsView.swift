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

    /// Changes which of the overlapping hints gets its preferred place.
    private var rotation = 0

    func rotate() {
        rotation += 1
        needsDisplay = true
    }

    private enum Style {
        static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        static let textColor = NSColor.white
        static let typedColor = NSColor(white: 1, alpha: 0.4)
        static let fill = NSColor(white: 0.08, alpha: 0.9)
        static let border = NSColor(white: 1, alpha: 0.18)
        static let horizontalPadding: CGFloat = 6
        static let verticalPadding: CGFloat = 2.5
        static let kerning: CGFloat = 0.6
        static let shadow: NSShadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowOffset = CGSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 3
            return shadow
        }()
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
        var visible = items.filter { $0.label.hasPrefix(typed) }
        guard !visible.isEmpty else { return }
        // Earlier hints win the free spots and later ones are drawn on top, so
        // reversing the order swaps every overlapping pair.
        if rotation.isMultiple(of: 2) == false {
            visible.reverse()
        }

        let texts = visible.map(attributedLabel)
        let rects = HintLayout.place(zip(visible, texts).map { item, text in
            HintLayout.Request(size: pillSize(for: text), anchor: item.anchor, elementFrame: item.elementFrame)
        })

        for (text, rect) in zip(texts, rects) {
            // Whole points (plus half for the 1 pt stroke) keep edges crisp.
            let pill = CGRect(origin: CGPoint(x: rect.minX.rounded() + 0.5, y: rect.minY.rounded() + 0.5), size: rect.size)
            guard pill.intersects(dirtyRect) else { continue }
            drawPill(pill, text: text)
        }
    }

    private func attributedLabel(for item: Item) -> NSAttributedString {
        let text = NSMutableAttributedString(string: item.label, attributes: [
            .font: Style.font,
            .foregroundColor: Style.textColor,
            .kern: Style.kerning,
        ])
        text.addAttribute(.foregroundColor, value: Style.typedColor, range: NSRange(location: 0, length: typed.utf16.count))
        return text
    }

    private func pillSize(for text: NSAttributedString) -> CGSize {
        let textSize = text.size()
        return CGSize(
            width: ceil(textSize.width + Style.horizontalPadding * 2),
            height: ceil(textSize.height + Style.verticalPadding * 2)
        )
    }

    private func drawPill(_ pill: CGRect, text: NSAttributedString) {
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        NSGraphicsContext.saveGraphicsState()
        Style.shadow.set()
        Style.fill.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        Style.border.setStroke()
        path.lineWidth = 1
        path.stroke()

        text.draw(at: CGPoint(x: pill.minX + Style.horizontalPadding, y: pill.minY + Style.verticalPadding))
    }
}
