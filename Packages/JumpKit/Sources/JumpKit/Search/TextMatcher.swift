import Foundation

/// Finds the query in the collected text.
public nonisolated enum TextMatcher {
    private static let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Every occurrence of `query` in `runs`, ignoring case and diacritics, in
    /// reading order: runs top to bottom and left to right, then by position
    /// inside each run. Each match starts with its run's frame.
    public static func matches<Node>(of query: String, in runs: [TextRun<Node>]) -> [TextMatch<Node>] {
        guard !query.allSatisfy(\.isWhitespace) else { return [] }
        let matched = runs.compactMap { run -> (run: TextRun<Node>, ranges: [NSRange])? in
            let ranges = occurrences(of: query, in: run.text)
            return ranges.isEmpty ? nil : (run, ranges)
        }
        return ReadingOrder.sorted(matched, frame: { $0.run.frame }).flatMap { run, ranges in
            ranges.map { TextMatch(run: run, range: $0, frame: run.frame) }
        }
    }

    /// Non-overlapping occurrences, as UTF-16 ranges. A range can be longer or
    /// shorter than the query when diacritics are composed differently.
    static func occurrences(of query: String, in text: String) -> [NSRange] {
        let text = text as NSString
        var ranges: [NSRange] = []
        var searchStart = 0
        while searchStart < text.length {
            let found = text.range(of: query, options: options,
                                   range: NSRange(location: searchStart, length: text.length - searchStart))
            guard found.location != NSNotFound, found.length > 0 else { break }
            ranges.append(found)
            searchStart = found.location + found.length
        }
        return ranges
    }
}
