import CoreGraphics
import Observation
import OSLog

/// Hint mode: scans the focused window, shows a label on every actionable
/// element, and acts on the element whose label the user types.
///
/// Dismissed by the hotkey, `Esc`, a typo, moving focus to another window, or losing the keyboard.
@Observable
public final class HintMode<Node: AccessibilityNode> {
    public typealias Scanner = (FrontmostApp) async throws -> ScanResult<Node>
    public typealias Performer = (HintAction, ScannedElement<Node>) async -> Void

    /// Last scan outcome, shown in the menu.
    public private(set) var lastSummary: String?
    public private(set) var isShowingHints = false

    @ObservationIgnored private let overlay: OverlayPresenting
    @ObservationIgnored private let input: ModeInputSource
    @ObservationIgnored private let isTrusted: () -> Bool
    @ObservationIgnored private let hintCharacters: () -> String
    @ObservationIgnored private let actionModifiers: () -> ActionModifiers
    @ObservationIgnored private let frontmostApp: () -> FrontmostApp?
    @ObservationIgnored private let prepareApp: (FrontmostApp) async -> Void
    @ObservationIgnored private let scan: Scanner
    @ObservationIgnored private let perform: Performer
    @ObservationIgnored private let logger = Logger(subsystem: "com.alvaldes.jump", category: "hints")

    /// The running scan and the last action (exposed to tests).
    @ObservationIgnored private(set) var scanTask: Task<Void, Never>?
    @ObservationIgnored private(set) var actionTask: Task<Void, Never>?
    @ObservationIgnored private var hints: [Hint<Node>] = []
    @ObservationIgnored private var keys = HintInput(labels: [])

    /// - Parameters:
    ///   - prepareApp: Runs before each scan (enables Chromium/Electron trees).
    public init(
        overlay: OverlayPresenting,
        input: ModeInputSource,
        isTrusted: @escaping () -> Bool,
        hintCharacters: @escaping () -> String,
        actionModifiers: @escaping () -> ActionModifiers = { .standard },
        frontmostApp: @escaping () -> FrontmostApp?,
        prepareApp: @escaping (FrontmostApp) async -> Void = { _ in },
        scan: @escaping Scanner,
        perform: @escaping Performer
    ) {
        self.overlay = overlay
        self.input = input
        self.isTrusted = isTrusted
        self.hintCharacters = hintCharacters
        self.actionModifiers = actionModifiers
        self.frontmostApp = frontmostApp
        self.prepareApp = prepareApp
        self.scan = scan
        self.perform = perform
    }

    /// Bound to the activation hotkey.
    public func toggle() {
        if isShowingHints || scanTask != nil {
            dismiss()
        } else {
            activate()
        }
    }

    public func dismiss() {
        scanTask?.cancel()
        scanTask = nil
        guard isShowingHints else { return }
        isShowingHints = false
        hints = []
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
            lastSummary = "No app to scan"
            return
        }
        // Latency budget (spec §3.9) is measured from the hotkey to hints on screen.
        let start = ContinuousClock.now
        scanTask = Task {
            await prepareApp(app)
            let result: ScanResult<Node>?
            do {
                result = try await scan(app)
            } catch {
                result = nil
            }
            // Dismissed while scanning; nothing to show.
            guard !Task.isCancelled else { return }
            scanTask = nil
            if let result {
                present(result, app: app, start: start)
            } else {
                lastSummary = "\(app.name): no focused window"
                logger.notice("Scan of \(app.name, privacy: .public) found no focused window")
            }
        }
    }

    private func present(_ result: ScanResult<Node>, app: FrontmostApp, start: ContinuousClock.Instant) {
        let scanned = ContinuousClock.now
        let hints = HintAssigner.assign(result.elements, characters: hintCharacters())
        var shown = scanned
        if let first = hints.first {
            self.hints = hints
            keys = HintInput(labels: hints.map(\.label))
            overlay.show(
                hints.map { HintPresentation(label: $0.label, anchor: $0.anchor, elementFrame: $0.element.frame) },
                focusPoint: CGPoint(x: first.element.frame.midX, y: first.element.frame.midY)
            )
            isShowingHints = true
            shown = ContinuousClock.now
            startListening(on: app)
        }

        let totalMs = Int((ContinuousClock.now - start) / .milliseconds(1))
        let scanMs = Int((scanned - start) / .milliseconds(1))
        let showMs = Int((shown - scanned) / .milliseconds(1))
        let truncated = result.isTruncated ? " (truncated)" : ""
        lastSummary = "\(app.name): \(hints.count) hints in \(totalMs) ms\(truncated)"
        logger.info("""
            Hints for \(app.name, privacy: .public): \(hints.count) hints, \(result.visitedCount) nodes, \
            scan \(scanMs) ms, shown in \(showMs) ms, on screen after \(totalMs) ms, truncated: \(result.isTruncated)
            """)
    }

    private func startListening(on app: FrontmostApp) {
        input.start(ModeInputHandler(
            keyDown: { [weak self] in self?.handleKeyDown($0) },
            focusLeft: { [weak self] in self?.dismiss() },
            keyboardLost: { [weak self] in self?.dismiss() }
        ), target: app)
    }

    private func handleKeyDown(_ press: KeyPress) {
        guard let key = HintKey(press) else { return }
        let result = keys.handle(key)
        logger.debug("Key \(String(describing: key), privacy: .public) -> \(String(describing: result), privacy: .public)")
        switch result {
        case .filtering(let typed):
            overlay.filter(typed: typed)
        case .matched(let label):
            guard let hint = hints.first(where: { $0.label == label }) else { return dismiss() }
            let action = actionModifiers().action(for: press)
            // Hide first so focus returns to the target app before it receives the action.
            dismiss()
            logger.info("Selected \(label, privacy: .public): \(String(describing: action), privacy: .public) on \(hint.element.role, privacy: .public)")
            let perform = self.perform
            actionTask = Task { await perform(action, hint.element) }
        case .cancelled:
            dismiss()
        case .rotate:
            overlay.rotate()
        case .ignored:
            break
        }
    }
}
