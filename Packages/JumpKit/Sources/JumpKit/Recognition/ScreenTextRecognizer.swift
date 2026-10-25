import CoreGraphics
import OSLog
import ScreenCaptureKit
import Vision

public enum ScreenTextRecognizerError: Error {
    case windowNotFound
}

/// Captures a window with ScreenCaptureKit and recognizes its text with
/// Vision (OCR). Needs Screen Recording access.
///
/// The ScreenCaptureKit window list takes 85–120 ms to load, so it is kept and
/// only reloaded when the window is not in it or its capture fails.
public final class ScreenTextRecognizer {
    private var windows: [SCWindow] = []
    private let logger = Logger(subsystem: "com.alvaldes.jump", category: "search")

    /// Largest difference, in points, between the cached window frame and the
    /// focused window's (sum over origin and size) still taken as the same window.
    static let frameTolerance: CGFloat = 4

    public init() {}

    /// Whether this process may capture the screen. Never prompts.
    public static var hasScreenRecordingAccess: Bool { CGPreflightScreenCaptureAccess() }

    /// Loads the window list ahead of the first search.
    public func prefetch() async {
        do {
            try await reloadWindows()
        } catch {
            logger.notice("OCR window list failed to load: \(String(describing: error), privacy: .public)")
        }
    }

    /// Recognized lines of the window of `pid` at `windowFrame` (AX coordinates).
    public func recognize(pid: pid_t, windowFrame: CGRect) async throws -> [TextRun<ScreenText>] {
        let lookupStart = ContinuousClock.now
        var reloaded = false
        var window = cachedWindow(pid: pid, frame: windowFrame, strict: true)
        if window == nil {
            try await reloadWindows()
            reloaded = true
            window = cachedWindow(pid: pid, frame: windowFrame, strict: false)
        }
        guard var window else { throw ScreenTextRecognizerError.windowNotFound }
        let lookupMs = Self.milliseconds(since: lookupStart)

        let captureStart = ContinuousClock.now
        let image: CGImage
        do {
            image = try await capture(window, size: windowFrame.size)
        } catch where !reloaded {
            // The cached window closed (a new one can sit at the same frame).
            try await reloadWindows()
            guard let fresh = cachedWindow(pid: pid, frame: windowFrame, strict: false) else {
                throw ScreenTextRecognizerError.windowNotFound
            }
            window = fresh
            reloaded = true
            image = try await capture(window, size: windowFrame.size)
        }
        let captureMs = Self.milliseconds(since: captureStart)

        let recognitionStart = ContinuousClock.now
        let lines = try await Self.recognizeText(in: image, window: windowFrame)
        let recognitionMs = Self.milliseconds(since: recognitionStart)
        logger.info("""
            OCR: window lookup \(lookupMs) ms\(reloaded ? "" : " (cached)", privacy: .public), \
            capture \(captureMs) ms (\(image.width)x\(image.height)), recognition \(recognitionMs) ms, \
            \(lines.count) lines
            """)
        return lines
    }

    /// Jumps to a recognized match: the hint action as pointer events at its
    /// center. There is no element, so no caret placement.
    @concurrent
    public nonisolated static func jump(_ action: HintAction, to match: TextMatch<ScreenText>) async {
        ElementActions.click(action, at: ScreenTextLayout.clickPoint(for: match))
    }

    // MARK: Capture

    private func reloadWindows() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        windows = content.windows.filter { $0.windowLayer == 0 }
    }

    /// The window of `pid` closest to `frame`; with `strict`, only one within
    /// `frameTolerance` (the cached list can be stale).
    private func cachedWindow(pid: pid_t, frame: CGRect, strict: Bool) -> SCWindow? {
        let candidates = windows.filter { $0.owningApplication?.processID == pid }
        guard let closest = candidates.min(by: { Self.distance($0.frame, frame) < Self.distance($1.frame, frame) })
        else { return nil }
        return !strict || Self.distance(closest.frame, frame) <= Self.frameTolerance ? closest : nil
    }

    /// At the display's pixel scale: Vision misses lines at 1x.
    private func capture(_ window: SCWindow, size: CGSize) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((size.width * scale).rounded())
        configuration.height = Int((size.height * scale).rounded())
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private nonisolated static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }

    // MARK: Vision

    /// The legacy request at `.fast`: the Swift `RecognizeTextRequest` at
    /// `.fast` finds almost nothing (spike, macOS 27.0.1), `.accurate` is too slow.
    @concurrent
    nonisolated static func recognizeText(in image: CGImage, window: CGRect) async throws -> [TextRun<ScreenText>] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            let wordBoxes = ScreenTextLayout.wordRanges(in: text).map { range in
                (try? candidate.boundingBox(for: range))?.boundingBox
            }
            return ScreenTextLayout.line(text: text, box: observation.boundingBox, wordBoxes: wordBoxes, window: window)
        }
    }

    private nonisolated static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start) / .milliseconds(1))
    }
}
