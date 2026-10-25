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
    @ObservationIgnored private let logger = Logger(subsystem: "com.alvaldes.jump", category: "search")

    /// Opening plus text collection, the word-bounds lookup of the current
    /// query, and the last jump (exposed to tests).
    @ObservationIgnored private(set) var scanTask: Task<Void, Never>?
    @ObservationIgnored private(set) var locateTask: Task<Void, Never>?
    @ObservationIgnored private(set) var actionTask: Task<Void, Never>?

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

    /// - Parameters:
    ///   - prepareApp: Runs before collecting (enables Chromium/Electron trees).
    ///   - locateLimit: How many matches, in reading order, get word bounds.
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
        locateLimit: Int = 100
    ) {
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
            isActive = true
            guard overlay.showSearch(presentation()) else {
                logger.error("Search box could not receive keys; leaving it")
                return dismiss()
            }
            let shownMs = Self.milliseconds(since: start)
            startListening(on: app)

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
        }
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
            jump(action)
        case .cancel:
            dismiss()
        case .ignored:
            break
        }
    }

    private func moveSelection(by offset: Int) {
        guard !matches.isEmpty else { return }
        selected = (selected + offset + matches.count) % matches.count
        overlay.showSearch(presentation())
    }

    /// Matches the current query, shows them at their runs' frames, then
    /// refines the first ones with word bounds off the main thread.
    private func refreshMatches() {
        guard let runs else { return }
        locateTask?.cancel()
        generation += 1
        matches = TextMatcher.matches(of: keys.query, in: runs)
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

    private func presentation() -> SearchPresentation {
        let status: SearchPresentation.Status = if runs == nil {
            .collecting
        } else if keys.query.allSatisfy(\.isWhitespace) {
            .idle
        } else if matches.isEmpty {
            .noMatches
        } else {
            .matches(selected: selected)
        }
        return SearchPresentation(query: keys.query, status: status, matches: matches.map(\.frame), windowFrame: target)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start) / .milliseconds(1))
    }
}
