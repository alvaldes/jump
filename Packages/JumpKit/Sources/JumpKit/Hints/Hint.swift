import CoreGraphics

/// A labelled element ready to be drawn and acted on.
public struct Hint<Node: AccessibilityNode>: Sendable {
    public let label: String
    public let element: ScannedElement<Node>

    public var anchor: HintAnchor {
        HintAnchor(role: element.role, frame: element.frame)
    }
}

/// Where a hint is drawn relative to its element, in AX coordinates.
public struct HintAnchor: Sendable, Equatable {
    public enum Alignment: Sendable {
        /// The hint is centered on `point`.
        case center
        /// The hint's bottom-left corner sits on `point`.
        case bottomLeading
    }

    public let point: CGPoint
    public let alignment: Alignment

    /// Distance from a row's leading edge to its hint and click point.
    public nonisolated static let rowLeadingInset: CGFloat = 24

    public nonisolated init(point: CGPoint, alignment: Alignment) {
        self.point = point
        self.alignment = alignment
    }

    public nonisolated init(role: String, frame: CGRect) {
        if role == "AXLink" {
            // Links often wrap across lines; centering would cover the text (Vimac #373).
            self.init(point: CGPoint(x: frame.minX, y: frame.maxY), alignment: .bottomLeading)
        } else if role == "AXRow" {
            // A row's label (icon, name) is at its leading side, not its center.
            self.init(point: CGPoint(x: frame.minX + min(Self.rowLeadingInset, frame.width / 2), y: frame.midY), alignment: .center)
        } else {
            self.init(point: CGPoint(x: frame.midX, y: frame.midY), alignment: .center)
        }
    }
}

public nonisolated enum HintAssigner {
    /// Labels elements in reading order, so the top-left ones get the shortest labels.
    public static func assign<Node>(_ elements: [ScannedElement<Node>], characters: String) -> [Hint<Node>] {
        let ordered = readingOrder(elements)
        let labels = HintLabels.make(count: ordered.count, characters: characters)
        return zip(labels, ordered).map { Hint(label: $0, element: $1) }
    }

    /// Groups elements into visual rows (top to bottom), each sorted left to right.
    static func readingOrder<Node>(_ elements: [ScannedElement<Node>]) -> [ScannedElement<Node>] {
        var rows: [[ScannedElement<Node>]] = []
        for element in elements.sorted(by: { $0.frame.midY < $1.frame.midY }) {
            if let rowStart = rows.last?.first, isSameRow(rowStart.frame, element.frame) {
                rows[rows.count - 1].append(element)
            } else {
                rows.append([element])
            }
        }
        return rows.flatMap { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }

    private static func isSameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let tolerance = max(4, min(a.height, b.height) / 2)
        return abs(a.midY - b.midY) <= tolerance
    }
}
