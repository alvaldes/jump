import CoreGraphics

/// Places hint pills so they cover each other as little as possible.
///
/// Works in any coordinate space, as long as anchors and element frames share it.
public nonisolated enum HintLayout {
    public struct Request: Sendable {
        public let size: CGSize
        public let anchor: HintAnchor
        public let elementFrame: CGRect

        public init(size: CGSize, anchor: HintAnchor, elementFrame: CGRect) {
            self.size = size
            self.anchor = anchor
            self.elementFrame = elementFrame
        }
    }

    private static let gap: CGFloat = 2

    /// Returns one rect per request, in order. A pill that collides with an
    /// earlier one slides right along its element; if it would leave the
    /// element, it keeps its preferred place (Space then rotates the stack).
    public static func place(_ requests: [Request]) -> [CGRect] {
        var placed: [CGRect] = []
        for request in requests {
            let preferred = preferredRect(for: request)
            let free = candidates(for: request, preferred: preferred, placed: placed).first { candidate in
                candidate.minX <= request.elementFrame.maxX && !placed.contains { $0.intersects(candidate) }
            }
            placed.append(free ?? preferred)
        }
        return placed
    }

    private static func preferredRect(for request: Request) -> CGRect {
        let point = request.anchor.point
        let origin = switch request.anchor.alignment {
        case .center: CGPoint(x: point.x - request.size.width / 2, y: point.y - request.size.height / 2)
        case .bottomLeading: point
        }
        return CGRect(origin: origin, size: request.size)
    }

    private static func candidates(for request: Request, preferred: CGRect, placed: [CGRect]) -> [CGRect] {
        let leading = CGRect(origin: CGPoint(x: request.elementFrame.minX, y: preferred.minY), size: preferred.size)
        let besideCollisions = placed
            .filter { $0.intersects(preferred) || $0.intersects(leading) }
            .map { CGRect(origin: CGPoint(x: $0.maxX + gap, y: preferred.minY), size: preferred.size) }
            .sorted { $0.minX < $1.minX }
        return [preferred, leading] + besideCollisions
    }
}
