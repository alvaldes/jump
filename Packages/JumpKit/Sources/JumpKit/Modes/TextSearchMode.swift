import CoreGraphics
import Observation
import OSLog

/// Text search mode: opens a search box over the focused window, collects its
/// visible text in the background while the user types, highlights every
/// match, and jumps to the selected one with `Return`.
///
/// Dismissed by the hotkey, `Esc`, moving focus to another window, or losing the keyboard.
@Observable
public final class TextSearchMode<Node: Sendable> {
    public typealias WindowFrameReader = (FrontmostApp) async throws -> CGRect
    public typealias Collector = (FrontmostApp) async throws -> [TextRun<Node>]
    /// The word bounds of a match, or `nil` when the app does not report them.
    public typealias Locator = (TextMatch<Node>) async -> CGRect?
    public typealias Performer = (HintAction, TextMatch<Node>) async -> Void

    /// Last search outcome, shown in the menu.
    public private(set) var lastSummary: String?
    public private(set) var isActive = false

    @ObservationIgnored private let overlay: SearchOverlayPresenting
    @ObservationIgnored private let input: ModeInputSource
    @ObservationIgnored private let isTrusted: () -> Bool
    @ObservationIgnored private let frontmostApp: () -> FrontmostApp?
    @ObservationIgnored private let prepareApp: (FrontmostApp) async -> Void
    @ObservationIgnored private let windowFrame: WindowFrameReader
    @ObservationIgnored private let collect: Collector
    @ObservationIgnored private let locate: Locator
    @ObservationIgnored private let perform: Performer
    @ObservationIgnored private let locateLimit: Int
    /// The OCR fallback; `nil` searches Accessibility text only.
    @ObservationIgnored private let screenText: ScreenTextSource?
    /// Returns when a search stops waiting for OCR and answers with
    /// Accessibility only.
    @ObservationIgnored private let recognitionDeadline: @Sendable () async -> Void
    @ObservationIgnored private let logger = Logger(subsystem: "com.alvaldes.jump", category: "search")

    /// Opening plus text collection, the word-bounds lookup of the current
    /// query, and the last jump (exposed to tests).
    @ObservationIgnored private(set) var scanTask: Task<Void, Never>?
    @ObservationIgnored private(set) var locateTask: Task<Void, Never>?
    @ObservationIgnored private(set) var actionTask: Task<Void, Never>?
    /// Screen text recognition of this search (exposed to tests).
    @ObservationIgnored private(set) var recognizeTask: Task<Void, Never>?
    @ObservationIgnored private(set) var recognitionTimeoutTask: Task<Void, Never>?

    @ObservationIgnored private var keys = SearchInput()
    @ObservationIgnored private var target = CGRect.null
    /// `nil` while the text is still being collected.
    @ObservationIgnored private var runs: [TextRun<Node>]?
    @ObservationIgnored private var matches: [TextMatch<Node>] = []
    /// Which matches already carry their word bounds.
    @ObservationIgnored private var located: [Bool] = []
    @ObservationIgnored private var selected = 0
    /// Bumped on every new match list, so word bounds of an older query are dropped.
    @ObservationIgnored private var generation = 0
    /// `Return` pressed while collecting: carried out once the text arrives,
    /// unless the query changes first.
    @ObservationIgnored private var pendingJump: HintAction?

    // OCR fallback: its matches are shown only while Accessibility has none.
    /// Whether this search recognizes screen text (read when it opens).
    @ObservationIgnored private var recognizesScreenText = false
    /// `nil` until recognition finishes.
    @ObservationIgnored private var screenRuns: [TextRun<ScreenText>]?
    @ObservationIgnored private var screenMatches: [TextMatch<ScreenText>] = []
    /// Bumped on every dismissal, so a closed search's recognition is dropped.
    @ObservationIgnored private var session = 0

    /// - Parameters:
    ///   - prepareApp: Runs before collecting (enables Chromium/Electron trees).
    ///   - locateLimit: How many matches, in reading order, get word bounds.
    ///   - screenText: Recognized text, searched when Accessibility has no match.
    public init(
        overlay: SearchOverlayPresenting,
        input: ModeInputSource,
        isTrusted: @escaping () -> Bool,
        frontmostApp: @escaping () -> FrontmostApp?,
        prepareApp: @escaping (FrontmostApp) async -> Void = { _ in },
        windowFrame: @escaping WindowFrameReader,
        collect: @escaping Collector,
        locate: @escaping Locator,
        perform: @escaping Performer,
        locateLimit: Int = 100,
        screenText: ScreenTextSource? = nil,
        recognitionDeadline: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: .seconds(2)) }
    ) {
        self.recognitionDeadline = recognitionDeadline
        self.overlay = overlay
        self.input = input
        self.isTrusted = isTrusted
        self.frontmostApp = frontmostApp
        self.prepareApp = prepareApp
        self.windowFrame = windowFrame
        self.collect = collect
        self.locate = locate
        self.perform = perform
        self.locateLimit = locateLimit
        self.screenText = screenText
    }

    /// Bound to the search hotkey.
    public func toggle() {
        if isActive || scanTask != nil {
            dismiss()
        } else {
            activate()
        }
    }

    public func dismiss() {
        scanTask?.cancel()
        scanTask = nil
        locateTask?.cancel()
        locateTask = nil
        generation += 1
        pendingJump = nil
        recognizeTask?.cancel()
        recognizeTask = nil
        recognitionTimeoutTask?.cancel()
        recognitionTimeoutTask = nil
        session += 1
        recognizesScreenText = false
        screenRuns = nil
        screenMatches = []
        guard isActive else { return }
        isActive = false
        runs = nil
        matches = []
        located = []
        // Stop listening before hiding: hiding takes the keyboard away from
        // the overlay, which must not be reported as a key loss.
        input.stop()
        overlay.hide()
    }

    private func activate() {
        guard isTrusted() else {
            lastSummary = "Accessibility access required"
            return
        }
        guard let app = frontmostApp() else {
            lastSummary = "No app to search"
            return
        }
        // Latency budget (spec §3.9) is measured from the hotkey to the box on screen.
        let start = ContinuousClock.now
        scanTask = Task {
            let frame = try? await windowFrame(app)
            guard !Task.isCancelled else { return }
            guard let frame else {
                scanTask = nil
                lastSummary = "\(app.name): no focused window"
                logger.notice("Search in \(app.name, privacy: .public) found no focused window")
                return
            }
            target = frame
            keys = SearchInput()
            runs = nil
            matches = []
            located = []
            selected = 0
            screenRuns = nil
            screenMatches = []
            isActive = true
            guard overlay.showSearch(presentation()) else {
                logger.error("Search box could not receive keys; leaving it")
                return dismiss()
            }
            let shownMs = Self.milliseconds(since: start)
            startListening(on: app)
            startRecognizing(app, frame: frame, since: start)

            await prepareApp(app)
            let collectStart = ContinuousClock.now
            let collected: [TextRun<Node>]
            do {
                collected = try await collect(app)
            } catch {
                collected = []
                logger.notice("Text collection in \(app.name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
            // Dismissed while collecting; nothing to show.
            guard !Task.isCancelled else { return }
            scanTask = nil
            runs = collected
            let collectMs = Self.milliseconds(since: collectStart)
            let totalMs = Self.milliseconds(since: start)
            lastSummary = "\(app.name): \(collected.count) texts in \(totalMs) ms"
            logger.info("""
                Search in \(app.name, privacy: .public): box shown after \(shownMs) ms, \
                \(collected.count) texts collected in \(collectMs) ms, ready after \(totalMs) ms
                """)
            refreshMatches()
            resolvePendingJump()
        }
    }

    /// Recognizes the window's text in parallel with the Accessibility collection.
    private func startRecognizing(_ app: FrontmostApp, frame: CGRect, since start: ContinuousClock.Instant) {
        guard let screenText, screenText.isEnabled() else { return }
        recognizesScreenText = true
        let thisSession = session
        recognizeTask = Task {
            let recognized: [TextRun<ScreenText>]
            do {
                recognized = try await screenText.recognize(app, frame)
            } catch {
                recognized = []
                logger.notice("OCR in \(app.name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
            // Dismissed (and maybe reopened) while recognizing.
            guard !Task.isCancelled, session == thisSession else { return }
            recognizeTask = nil
            recognitionTimeoutTask?.cancel()
            recognitionTimeoutTask = nil
            screenRuns = recognized
            logger.info("OCR in \(app.name, privacy: .public): \(recognized.count) lines ready after \(Self.milliseconds(since: start)) ms")
            // Only queries without Accessibility matches change.
            if runs != nil, matches.isEmpty {
                refreshMatches()
            }
            resolvePendingJump()
        }
        // A capture or recognition that hangs must not keep the search at
        // "Searching…" (and a pending Return waiting) forever.
        let deadline = recognitionDeadline
        recognitionTimeoutTask = Task {
            await deadline()
            guard !Task.isCancelled, session == thisSession, screenRuns == nil else { return }
            recognizeTask?.cancel()
            recognizeTask = nil
            recognitionTimeoutTask = nil
            screenRuns = []
            logger.notice("OCR in \(app.name, privacy: .public) timed out; using Accessibility only")
            if runs != nil, matches.isEmpty {
                refreshMatches()
            }
            resolvePendingJump()
        }
    }

    /// The current query has no final answer yet: Accessibility is still
    /// collecting, or found nothing while OCR may still find it.
    private var awaitsResults: Bool {
        runs == nil || (matches.isEmpty && recognizesScreenText && screenRuns == nil)
    }

    /// Carries out a Return pressed before the results were in.
    private func resolvePendingJump() {
        guard let action = pendingJump, !awaitsResults else { return }
        pendingJump = nil
        jump(action)
    }

    private func startListening(on app: FrontmostApp) {
        input.start(ModeInputHandler(
            keyDown: { [weak self] in self?.handleKeyDown($0) },
            focusLeft: { [weak self] in self?.dismiss() },
            keyboardLost: { [weak self] in self?.dismiss() }
        ), target: app)
    }

    private func handleKeyDown(_ press: KeyPress) {
        switch keys.handle(press) {
        case .edited:
            pendingJump = nil
            if runs == nil {
                overlay.showSearch(presentation())
            } else {
                refreshMatches()
            }
        case .next:
            moveSelection(by: 1)
        case .previous:
            moveSelection(by: -1)
        case .jump(let action):
            if awaitsResults {
                pendingJump = action
            } else {
                jump(action)
            }
        case .cancel:
            dismiss()
        case .ignored:
            break
        }
    }

    /// How many matches the overlay shows, from whichever source has them.
    private var matchCount: Int { matches.isEmpty ? screenMatches.count : matches.count }

    private func moveSelection(by offset: Int) {
        let count = matchCount
        guard count > 0 else { return }
        selected = (selected + offset + count) % count
        overlay.showSearch(presentation())
    }

    /// Matches the current query, shows them at their runs' frames, then
    /// refines the first ones with word bounds off the main thread.
    private func refreshMatches() {
        guard let runs else { return }
        locateTask?.cancel()
        generation += 1
        matches = TextMatcher.matches(of: keys.query, in: runs)
        screenMatches = matches.isEmpty ? ScreenTextLayout.matches(of: keys.query, in: screenRuns ?? []) : []
        located = Array(repeating: false, count: matches.count)
        selected = 0
        overlay.showSearch(presentation())
        guard !matches.isEmpty else {
            locateTask = nil
            return
        }

        let thisGeneration = generation
        let pending = Array(matches.prefix(locateLimit).enumerated())
        let locate = self.locate
        locateTask = Task {
            var frames: [(index: Int, frame: CGRect)] = []
            for (index, match) in pending {
                guard !Task.isCancelled else { return }
                if let frame = await locate(match) {
                    frames.append((index, frame))
                }
            }
            // A newer query or a dismissal replaced these matches.
            guard !Task.isCancelled, generation == thisGeneration else { return }
            for (index, frame) in frames {
                matches[index].frame = frame
            }
            for (index, _) in pending {
                located[index] = true
            }
            overlay.showSearch(presentation())
        }
    }

    private func jump(_ action: HintAction) {
        if matches.isEmpty, let screenText, screenMatches.indices.contains(selected) {
            return jumpOnScreen(action, to: screenMatches[selected], via: screenText)
        }
        guard matches.indices.contains(selected) else { return }
        let match = matches[selected]
        let isLocated = located[selected]
        // Hide first so focus returns to the target app before it receives the jump.
        dismiss()
        logger.info("Jump: \(String(describing: action), privacy: .public) on \(match.run.role, privacy: .public)")
        let locate = self.locate
        let perform = self.perform
        actionTask = Task {
            var match = match
            // Return can come before the word bounds of this match did.
            if !isLocated, let frame = await locate(match) {
                match.frame = frame
            }
            await perform(action, match)
        }
    }

    /// Recognized matches already carry word boxes; there is no caret to place.
    private func jumpOnScreen(_ action: HintAction, to match: TextMatch<ScreenText>, via screenText: ScreenTextSource) {
        dismiss()
        logger.info("Jump: \(String(describing: action), privacy: .public) on \(match.run.role, privacy: .public)")
        let perform = screenText.perform
        actionTask = Task { await perform(action, match) }
    }

    private func presentation() -> SearchPresentation {
        let status: SearchPresentation.Status = if runs == nil {
            .collecting
        } else if keys.query.allSatisfy(\.isWhitespace) {
            .idle
        } else if !matches.isEmpty || !screenMatches.isEmpty {
            .matches(selected: selected)
        } else if recognizesScreenText, screenRuns == nil {
            // OCR may still find it.
            .collecting
        } else {
            .noMatches
        }
        let frames = matches.isEmpty ? screenMatches.map(\.frame) : matches.map(\.frame)
        return SearchPresentation(query: keys.query, status: status, matches: frames, windowFrame: target)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start) / .milliseconds(1))
    }
}
