import CoreGraphics
import Foundation
import Testing
@testable import JumpKit

@Suite("Screen text layout")
struct ScreenTextTests {
    private static let window = CGRect(x: 100, y: 50, width: 800, height: 600)

    /// Normalized fractions do not land on exact binary values; compare to 1/100 point.
    private static func r(_ rect: CGRect) -> CGRect {
        func round(_ value: CGFloat) -> CGFloat { (value * 100).rounded() / 100 }
        return CGRect(x: round(rect.minX), y: round(rect.minY), width: round(rect.width), height: round(rect.height))
    }

    private static func axFrame(_ box: CGRect) -> CGRect {
        r(ScreenTextLayout.axFrame(normalized: box, window: window))
    }

    // MARK: Coordinates

    @Test func normalizedBottomLeftBoxesBecomeGlobalTopLeftFrames() {
        // Vision: origin at the bottom left of the image, sides as fractions.
        let box = CGRect(x: 0.25, y: 0.5, width: 0.1, height: 0.05)
        #expect(Self.axFrame(box) == CGRect(x: 300, y: 320, width: 80, height: 30))
    }

    @Test func theWholeImageIsTheWholeWindow() {
        let all = CGRect(x: 0, y: 0, width: 1, height: 1)
        #expect(Self.axFrame(all) == Self.window)
    }

    @Test func theCaptureScaleDoesNotChangeTheFrame() {
        // The same word, found in a 1x capture and in a 2x (Retina) capture.
        func normalized(_ pixels: CGRect, imageWidth: CGFloat, imageHeight: CGFloat) -> CGRect {
            CGRect(x: pixels.minX / imageWidth, y: 1 - pixels.maxY / imageHeight,
                   width: pixels.width / imageWidth, height: pixels.height / imageHeight)
        }
        let nominal = normalized(CGRect(x: 100, y: 50, width: 20, height: 10), imageWidth: 800, imageHeight: 600)
        let retina = normalized(CGRect(x: 200, y: 100, width: 40, height: 20), imageWidth: 1600, imageHeight: 1200)
        let expected = CGRect(x: 200, y: 100, width: 20, height: 10)
        #expect(Self.axFrame(nominal) == expected)
        #expect(Self.axFrame(retina) == expected)
    }

    // MARK: Lines and words

    @Test func wordsAreSplitOnWhitespace() {
        let text = "  git  status --short"
        let words = ScreenTextLayout.wordRanges(in: text).map { String(text[$0]) }
        #expect(words == ["git", "status", "--short"])
    }

    /// "git status": line box spans the window's top strip; each word has its own box.
    private static func gitStatus(wordBoxes: [CGRect?]) -> TextRun<ScreenText> {
        ScreenTextLayout.line(text: "git status", box: CGRect(x: 0, y: 0.9, width: 0.5, height: 0.05),
                              wordBoxes: wordBoxes, window: Self.window)
    }

    @Test func aRecognizedLineIsARunInWindowCoordinates() {
        let run = Self.gitStatus(wordBoxes: [CGRect(x: 0, y: 0.9, width: 0.1, height: 0.05), nil])
        #expect(run.text == "git status")
        #expect(Self.r(run.frame) == CGRect(x: 100, y: 80, width: 400, height: 30))
        #expect(run.isEditable == false)
        // Words without a box are left out; their matches use the line.
        #expect(run.node.words.map(\.range) == [NSRange(location: 0, length: 3)])
        #expect(run.node.words.map { Self.r($0.frame) } == [CGRect(x: 100, y: 80, width: 80, height: 30)])
    }

    private static let boxed = gitStatus(wordBoxes: [
        CGRect(x: 0, y: 0.9, width: 0.1, height: 0.05),
        CGRect(x: 0.15, y: 0.9, width: 0.2, height: 0.05),
    ])

    @Test func aMatchInsideAWordTakesThatWordsFrame() {
        let matches = ScreenTextLayout.matches(of: "TAT", in: [Self.boxed])
        #expect(matches.map(\.range) == [NSRange(location: 5, length: 3)])
        #expect(matches.map { Self.r($0.frame) } == [CGRect(x: 220, y: 80, width: 160, height: 30)])
    }

    @Test func aMatchAcrossWordsSpansThem() {
        let matches = ScreenTextLayout.matches(of: "t s", in: [Self.boxed])
        #expect(matches.map { Self.r($0.frame) } == [CGRect(x: 100, y: 80, width: 280, height: 30)])
    }

    @Test func aMatchInAWordWithoutABoxTakesTheLineFrame() {
        let run = Self.gitStatus(wordBoxes: [CGRect(x: 0, y: 0.9, width: 0.1, height: 0.05), nil])
        let matches = ScreenTextLayout.matches(of: "status", in: [run])
        #expect(matches.map(\.frame) == [run.frame])
    }

    @Test func matchingFollowsTheAccessibilityRules() {
        // Case and diacritics ignored, reading order (top line first).
        let lower = ScreenTextLayout.line(text: "Résumé", box: CGRect(x: 0, y: 0.1, width: 0.2, height: 0.05),
                                          wordBoxes: [nil], window: Self.window)
        let upper = ScreenTextLayout.line(text: "resume", box: CGRect(x: 0, y: 0.8, width: 0.2, height: 0.05),
                                          wordBoxes: [nil], window: Self.window)
        let matches = ScreenTextLayout.matches(of: "RESUME", in: [lower, upper])
        #expect(matches.map(\.run.text) == ["resume", "Résumé"])
    }

    @Test func jumpsClickAtTheCenterOfTheMatch() {
        let match = ScreenTextLayout.matches(of: "status", in: [Self.boxed])[0]
        let point = ScreenTextLayout.clickPoint(for: match)
        #expect((point.x * 100).rounded() / 100 == 300)
        #expect((point.y * 100).rounded() / 100 == 95)
    }
}

@Suite("Screen text window lookup")
struct ScreenTextWindowLookupTests {
    private let focused = CGRect(x: 100, y: 100, width: 800, height: 600)

    @Test func theClosestWindowWithinTheToleranceIsCaptured() {
        let frames = [CGRect(x: 900, y: 100, width: 800, height: 600), CGRect(x: 102, y: 101, width: 800, height: 600)]
        #expect(ScreenTextRecognizer.closestWindow(in: frames, to: focused, within: 4) == 1)
    }

    /// Another window of the same app must never stand in for the focused one:
    /// its text would be mapped onto the focused window's frame.
    @Test func aSiblingWindowElsewhereIsNeverCaptured() {
        let frames = [CGRect(x: 900, y: 100, width: 800, height: 600)]
        #expect(ScreenTextRecognizer.closestWindow(in: frames, to: focused, within: ScreenTextRecognizer.reloadedFrameTolerance) == nil)
    }

    @Test func aFreshListAcceptsSmallFrameDifferences() {
        let frames = [CGRect(x: 100, y: 110, width: 800, height: 590)]
        #expect(ScreenTextRecognizer.closestWindow(in: frames, to: focused, within: ScreenTextRecognizer.reloadedFrameTolerance) == 0)
    }
}
