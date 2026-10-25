import CoreGraphics
import OSLog

/// Scroll mode: Vim keys scroll the focused window's largest scroll area;
/// `Tab` moves to the next one. Exits with `Esc`, the hotkey, switching apps,
/// or losing the keyboard.
public final class ScrollMode<Driver: ScrollDriving> {
    public typealias Control = Driver.Control
    public typealias TargetFinder = (_ app: FrontmostApp, _ screens: [CGRect]) async throws -> [ScrollTarget<Control>]

    public private(set) var isActive = false

    private let overlay: OverlayPresenting
    private let pointer: PointerControlling
    private let input: ModeInputSource
    private let driver: Driver
    private let isTrusted: () -> Bool
    private let frontmostApp: () -> FrontmostApp?
    private let screens: () -> [CGRect]
    private let findTargets: TargetFinder
    private let sequenceDelay: Duration
    private let logger = Logger(subsystem: "com.alvaldes.jump", category: "scroll")

    /// The running scroll-area search (exposed to tests).
    private(set) var scanTask: Task<Void, Never>?
    private var targets: [ScrollTarget<Control>] = []
    private var activeIndex = 0
    private var keys = ScrollInput()
    private var sequenceTimeout: Task<Void, Never>?
    /// Where the pointer was before scroll mode moved it (wheel areas only).
    private var originalPointer: CGPoint?
    private var output = ScrollOutput<Control>.wheel
    /// The direction key whose release stops the current scroll, and what it started.
    private var heldKeyCode: UInt16?
    private var heldCommand: ScrollCommand?

    /// - Parameter sequenceDelay: How long a half-typed `g` waits (Vimac: 250 ms).
    public init(
        overlay: OverlayPresenting,
        pointer: PointerControlling,
        input: ModeInputSource,
        driver: Driver,
        isTrusted: @escaping () -> Bool,
        frontmostApp: @escaping () -> FrontmostApp?,
        screens: @escaping () -> [CGRect],
        findTargets: @escaping TargetFinder,
        sequenceDelay: Duration = .milliseconds(250)
    ) {
        self.overlay = overlay
        self.pointer = pointer
        self.input = input
        self.driver = driver
        self.isTrusted = isTrusted
        self.frontmostApp = frontmostApp
        self.screens = screens
        self.findTargets = findTargets
        self.sequenceDelay = sequenceDelay
        driver.onAccessibilityFailure = { [weak self] control in self?.fallBackToWheel(after: control) }
    }

    /// Bound to the scroll-mode hotkey.
    public func toggle() {
        if isActive || scanTask != nil {
            deactivate()
        } else {
            activate()
        }
    }

    public func deactivate() {
        scanTask?.cancel()
        scanTask = nil
        guard isActive else { return }
        isActive = false
        stopScrolling()
        sequenceTimeout?.cancel()
        // Stop listening before hiding: hiding takes the keyboard away from
        // the overlay, which must not be reported as a key loss.
        input.stop()
        overlay.hide()
        if let originalPointer {
            pointer.move(to: originalPointer)
        }
        originalPointer = nil
        targets = []
    }

    private func activate() {
        guard isTrusted(), let app = frontmostApp() else { return }
        let start = ContinuousClock.now
        let screens = screens()
        scanTask = Task {
            let found = (try? await findTargets(app, screens)) ?? []
            guard !Task.isCancelled else { return }
            scanTask = nil
            // The user switched apps during the search: these areas belong to
            // a window that is no longer in front.
            guard frontmostApp()?.pid == app.pid else {
                logger.info("App changed while searching scroll areas; not entering scroll mode")
                return
            }
            guard !found.isEmpty else {
                logger.notice("No scroll area in \(app.name, privacy: .public)")
                return
            }
            targets = found
            isActive = true
            keys = ScrollInput()
            guard setActiveArea(0) else {
                logger.error("Scroll mode could not receive keys; leaving it")
                return deactivate()
            }
            startListening()
            let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
            logger.info("Scroll mode in \(app.name, privacy: .public): \(found.count) areas, ready after \(milliseconds) ms")
        }
    }

    private func startListening() {
        input.start(ModeInputHandler(
            keyDown: { [weak self] in self?.handleKeyDown($0) },
            keyUp: { [weak self] keyCode in
                // Only releasing the key that started the scroll stops it.
                if keyCode == self?.heldKeyCode { self?.stopScrolling() }
            },
            otherAppActivated: { [weak self] in self?.deactivate() },
            // Key-up events would no longer arrive and a held key would
            // scroll forever.
            keyboardLost: { [weak self] in self?.deactivate() }
        ))
    }

    @discardableResult
    private func setActiveArea(_ index: Int) -> Bool {
        stopScrolling()
        activeIndex = index
        let target = targets[index]
        let receivesKeys = overlay.showOutline(target.frame)
        if let control = target.control {
            // Scroll bars are driven directly, so the pointer stays free.
            output = .accessibility(control)
        } else {
            useWheel(for: target.frame)
        }
        return receivesKeys
    }

    /// Wheel events go to whatever is under the pointer, so it moves onto the area.
    private func useWheel(for frame: CGRect) {
        output = .wheel
        if originalPointer == nil {
            originalPointer = pointer.location
        }
        pointer.move(to: CGPoint(x: frame.midX, y: frame.midY))
    }

    /// The app stopped accepting scroll bar writes: continue with wheel events,
    /// including a scroll the user is still holding.
    private func fallBackToWheel(after failed: Control) {
        // A late report about an area the user already left with Tab is stale.
        guard isActive, case .accessibility(let current) = output, current == failed else { return }
        logger.notice("Accessibility scrolling failed; using wheel events for this area")
        targets[activeIndex].control = nil
        useWheel(for: targets[activeIndex].frame)
        if let heldCommand {
            start(heldCommand)
        }
    }

    private func stopScrolling() {
        driver.stop()
        heldKeyCode = nil
        heldCommand = nil
    }

    private func handleKeyDown(_ press: KeyPress) {
        // Holding a key scrolls until key up; auto-repeat must not restart it.
        // ⌘J or ⌃D are app shortcuts, not scroll commands.
        guard !press.isRepeat, !press.isShortcut, let key = ScrollKey(press) else { return }
        sequenceTimeout?.cancel()
        switch keys.handle(key) {
        case .command(.scroll(let direction)):
            startHeld(.scroll(direction), keyCode: press.keyCode)
        case .command(.halfPage(let direction)):
            startHeld(.halfPage(direction), keyCode: press.keyCode)
        case .command(.top):
            driver.scrollToEdge(top: true, via: output)
        case .command(.bottom):
            driver.scrollToEdge(top: false, via: output)
        case .command(.nextArea):
            setActiveArea((activeIndex + 1) % targets.count)
        case .command(.exit):
            deactivate()
        case .pending:
            sequenceTimeout = Task { [sequenceDelay] in
                try? await Task.sleep(for: sequenceDelay)
                guard !Task.isCancelled else { return }
                keys.reset()
            }
        case .ignored:
            break
        }
    }

    /// Starts a scroll that lasts until `keyCode` is released.
    private func startHeld(_ command: ScrollCommand, keyCode: UInt16) {
        start(command)
        heldKeyCode = keyCode
        heldCommand = command
    }

    private func start(_ command: ScrollCommand) {
        switch command {
        case .scroll(let direction):
            driver.startSmooth(direction, via: output)
        case .halfPage(let direction):
            driver.startHalfPage(direction, in: targets[activeIndex].frame, via: output)
        default:
            break
        }
    }
}
