import AppKit

/// Draws every hint of one screen in a single pass (no view per hint),
/// so hundreds of hints stay cheap to show.
final class HintsView: NSView {
    struct Item: Equatable {
        let label: String
        /// Anchor in this view's coordinates (bottom-left origin).
        let point: CGPoint
        let alignment: HintAnchor.Alignment
    }

    var items: [Item] = [] {
        didSet { if items != oldValue { needsDisplay = true } }
    }

    private enum Style {
        static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        static let textColor = NSColor.white
        static let fill = NSColor(white: 0.08, alpha: 0.9)
        static let border = NSColor(white: 1, alpha: 0.18)
        static let horizontalPadding: CGFloat = 6
        static let verticalPadding: CGFloat = 2.5
        static let shadow: NSShadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowOffset = CGSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 3
            return shadow
        }()
        static let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .kern: 0.6,
        ]
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
        for item in items {
            let text = NSAttributedString(string: item.label, attributes: Style.textAttributes)
            let pill = pillRect(for: item, textSize: text.size())
            guard pill.intersects(dirtyRect) else { continue }

            let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
            NSGraphicsContext.saveGraphicsState()
            Style.shadow.set()
            Style.fill.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            Style.border.setStroke()
            path.lineWidth = 1
            path.stroke()

            text.draw(at: CGPoint(
                x: pill.minX + Style.horizontalPadding,
                y: pill.minY + Style.verticalPadding
            ))
        }
    }

    private func pillRect(for item: Item, textSize: CGSize) -> CGRect {
        let size = CGSize(
            width: ceil(textSize.width + Style.horizontalPadding * 2),
            height: ceil(textSize.height + Style.verticalPadding * 2)
        )
        let origin: CGPoint = switch item.alignment {
        case .center:
            CGPoint(x: item.point.x - size.width / 2, y: item.point.y - size.height / 2)
        case .bottomLeading:
            item.point
        }
        // Whole points (plus half for the 1 pt stroke) keep edges crisp.
        return CGRect(origin: CGPoint(x: origin.x.rounded() + 0.5, y: origin.y.rounded() + 0.5), size: size)
    }
}
