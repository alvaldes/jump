import CoreGraphics
import Foundation
import Testing
@testable import JumpKit

@Suite("TextMatcher")
struct TextMatcherTests {
    private func run(_ text: String, id: String = "", x: CGFloat = 10, y: CGFloat = 10) -> TextRun<String> {
        TextRun(text: text, frame: CGRect(x: x, y: y, width: 200, height: 20), role: "AXStaticText",
                isEditable: false, node: id.isEmpty ? text : id)
    }

    /// Each match as "node:location+length".
    private func found(_ query: String, in runs: [TextRun<String>]) -> [String] {
        TextMatcher.matches(of: query, in: runs).map { "\($0.run.node):\($0.range.location)+\($0.range.length)" }
    }

    @Test func ignoresCase() {
        #expect(found("SAVE", in: [run("Save changes")]) == ["Save changes:0+4"])
    }

    @Test func ignoresDiacritics() {
        #expect(found("cafe", in: [run("Un café")]) == ["Un café:3+4"])
        #expect(found("canción", in: [run("cancion")]) == ["cancion:0+7"])
    }

    @Test func findsEveryOccurrenceInARun() {
        #expect(found("ab", in: [run("ab cab abab")]) == ["ab cab abab:0+2", "ab cab abab:4+2", "ab cab abab:7+2", "ab cab abab:9+2"])
    }

    @Test func rangesCountUTF16Units() {
        // 👋 is two UTF-16 units; the accent is precomposed (one unit).
        let text = "👋 Ñandú y más"
        let matches = TextMatcher.matches(of: "mas", in: [run(text)])
        #expect(matches.map(\.range) == [NSRange(location: 11, length: 3)])
        #expect(matches.first.map { (text as NSString).substring(with: $0.range) } == "más")
    }

    @Test func matchesStartAtTheRunFrame() {
        let source = run("hello", x: 40, y: 70)
        #expect(TextMatcher.matches(of: "ell", in: [source]).map(\.frame) == [source.frame])
    }

    @Test func ordersMatchesInReadingOrder() {
        let runs = [
            run("go bottom", id: "bottom", x: 10, y: 300),
            run("go right", id: "topRight", x: 300, y: 10),
            run("go left", id: "topLeft", x: 10, y: 14),  // same visual row as topRight
        ]
        #expect(found("go", in: runs) == ["topLeft:0+2", "topRight:0+2", "bottom:0+2"])
    }

    @Test(arguments: ["", " ", "  \n"])
    func anEmptyQueryMatchesNothing(query: String) {
        #expect(found(query, in: [run("some text")]).isEmpty)
    }
}
