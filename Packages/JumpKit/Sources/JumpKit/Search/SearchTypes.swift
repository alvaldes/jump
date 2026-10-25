import Foundation

// Shared contract of text search mode: what the controller collects and
// matches, and what the overlay draws.

/// A piece of visible text in the target window, as one accessibility element
/// exposes it.
public nonisolated struct TextRun<Node: Sendable>: Sendable {
    public let text: String
    /// Element frame in AX coordinates (top-left origin, global).
    public let frame: CGRect
    public let role: String
    /// Text fields and areas: jumping places the caret instead of clicking.
    public let isEditable: Bool
    public let node: Node

    public init(text: String, frame: CGRect, role: String, isEditable: Bool, node: Node) {
        self.text = text
        self.frame = frame
        self.role = role
        self.isEditable = isEditable
        self.node = node
    }
}

/// One occurrence of the query inside a run.
public nonisolated struct TextMatch<Node: Sendable>: Sendable {
    public let run: TextRun<Node>
    /// UTF-16 range inside `run.text` (what `AXBoundsForRange` and
    /// `AXSelectedTextRange` expect).
    public let range: NSRange
    /// Where the match is on screen, in AX coordinates: the word bounds when
    /// the app reports them, else the run's frame.
    public var frame: CGRect

    public init(run: TextRun<Node>, range: NSRange, frame: CGRect) {
        self.run = run
        self.range = range
        self.frame = frame
    }
}

/// What the search overlay shows. All frames are in AX coordinates.
public nonisolated struct SearchPresentation: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// Text is still being collected.
        case collecting
        /// Query is empty.
        case idle
        case noMatches
        /// `selected` is an index into `matches`.
        case matches(selected: Int)
    }

    public var query: String
    public var status: Status
    /// Highlighted matches, in reading order.
    public var matches: [CGRect]
    /// The target window; the search box sits at its top center.
    public var windowFrame: CGRect

    public init(query: String, status: Status, matches: [CGRect], windowFrame: CGRect) {
        self.query = query
        self.status = status
        self.matches = matches
        self.windowFrame = windowFrame
    }
}

/// The overlay as text search mode uses it.
public protocol SearchOverlayPresenting: AnyObject {
    var isVisible: Bool { get }
    /// Shows or updates the search box and highlights. The first call makes
    /// the panel over `windowFrame` key; returns whether it could take the keyboard.
    @discardableResult func showSearch(_ presentation: SearchPresentation) -> Bool
    func hide()
}
