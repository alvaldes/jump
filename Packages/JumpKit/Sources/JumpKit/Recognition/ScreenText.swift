import Foundation

/// A line of text recognized on screen (OCR), as text search matches it: the
/// node of its `TextRun`, which carries the line's text and frame.
public nonisolated struct ScreenText: Sendable, Equatable {
    /// A word of the line with its own box.
    public struct Word: Sendable, Equatable {
        /// UTF-16 range inside the line's text.
        public let range: NSRange
        /// In AX coordinates (top-left origin, global).
        public let frame: CGRect

        public init(range: NSRange, frame: CGRect) {
            self.range = range
            self.frame = frame
        }
    }

    /// Only the words Vision gave a box for.
    public let words: [Word]

    public init(words: [Word]) {
        self.words = words
    }

    /// The boxes of the words `range` touches, joined, or `nil` when none of
    /// them has a box.
    public func frame(for range: NSRange) -> CGRect? {
        let touched = words.filter { NSIntersectionRange($0.range, range).length > 0 }
        guard let first = touched.first else { return nil }
        return touched.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }
}

/// Turns what Vision recognized in a window capture into text search runs and
/// matches.
public nonisolated enum ScreenTextLayout {
    /// Role of recognized runs, as logged on jumps.
    public static let role = "OCRText"

    /// A Vision box (normalized to the image, bottom-left origin) in AX
    /// coordinates. The capture is exactly the window, so its scale does not
    /// matter.
    public static func axFrame(normalized box: CGRect, window: CGRect) -> CGRect {
        CGRect(x: window.minX + box.minX * window.width,
               y: window.minY + (1 - box.maxY) * window.height,
               width: box.width * window.width,
               height: box.height * window.height)
    }

    /// Words of a line: runs of non-whitespace characters.
    public static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            if text[index].isWhitespace {
                if let wordStart = start { ranges.append(wordStart..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let start { ranges.append(start..<text.endIndex) }
        return ranges
    }

    /// One recognized line as a run. `wordBoxes` holds the normalized box of
    /// each of `wordRanges(in: text)`, `nil` when Vision gave none.
    public static func line(text: String, box: CGRect, wordBoxes: [CGRect?], window: CGRect) -> TextRun<ScreenText> {
        let words = zip(wordRanges(in: text), wordBoxes).compactMap { range, box in
            box.map { ScreenText.Word(range: NSRange(range, in: text), frame: axFrame(normalized: $0, window: window)) }
        }
        return TextRun(text: text, frame: axFrame(normalized: box, window: window), role: role, isEditable: false,
                       node: ScreenText(words: words))
    }

    /// Where a jump to the match clicks.
    public static func clickPoint(for match: TextMatch<ScreenText>) -> CGPoint {
        CGPoint(x: match.frame.midX, y: match.frame.midY)
    }

    /// The query's matches in recognized lines, with the rules of `TextMatcher`;
    /// each match takes the frame of the words it covers.
    public static func matches(of query: String, in runs: [TextRun<ScreenText>]) -> [TextMatch<ScreenText>] {
        TextMatcher.matches(of: query, in: runs).map { match in
            var match = match
            if let frame = match.run.node.frame(for: match.range) {
                match.frame = frame
            }
            return match
        }
    }
}
