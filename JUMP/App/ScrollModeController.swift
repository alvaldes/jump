import AppKit
import JumpKit
import OSLog

/// Scroll mode: Vim keys scroll the focused window's largest scroll area;
/// `Tab` moves to the next one. Exits with `Esc`, the hotkey, or switching apps.
@Observable
final class ScrollModeController {
    private let permission: AccessibilityPermission
    private let overlay: HintOverlay
    private let scroller = Scroller()
    private let logger = Logger(subsystem: "com.alvaldes.jump", category: "scroll")

    private var scanTask: Task<Void, Never>?
    private var targets: [ScrollTarget] = []
    private var activeIndex = 0
    private var input = ScrollInput()
    private var sequenceTimeout: Task<Void, Never>?
    /// Where the pointer was before scroll mode moved it (wheel fallback only).
    private var originalPointer: CGPoint?
    /// How the active area is scrolled.
    private var output = ScrollOutput.wheel
    /// The direction key whose release stops the current scroll, and what it started.
    private var heldKeyCode: UInt16?
    private var heldCommand: ScrollCommand?
    private var keyMonitor: Any?
    private var appSwitchObserver: (any NSObjectProtocol)?
    private var keyLossObserver: (any NSObjectProtocol)?

    private(set) var isActive = false

    /// Vimac's delay before a half-typed `g` sequence is dropped.
    private static let sequenceDelay: Duration = .milliseconds(250)

    private enum KeyCode {
        static let escape: UInt16 = 53
        static let tab: UInt16 = 48
    }

    init(permission: AccessibilityPermission, overlay: HintOverlay) {
        self.permission = permission
        self.overlay = overlay
        scroller.onAccessibilityFailure = { [weak self] control in self?.fallBackToWheel(after: control) }
    }

    /// Bound to the scroll-mode hotkey.
    func toggle() {
        if isActive || scanTask != nil {
            deactivate()
        } else {
            activate()
        }
    }

    func deactivate() {
        scanTask?.cancel()
        scanTask = nil
        guard isActive else { return }
        isActive = false
        stopScrolling()
        sequenceTimeout?.cancel()
        overlay.hide()
        stopListening()
        if let originalPointer {
            Pointer.move(to: originalPointer)
        }
        originalPointer = nil
        targets = []
    }

    private func activate() {
        guard permission.isTrusted,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }

        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown app"
        let start = ContinuousClock.now
        let screens = Self.screenFramesInAXCoordinates()
        scanTask = Task {
            let found = (try? await FocusedWindowScanner.scrollTargets(pid: pid, screens: screens)) ?? []
            guard !Task.isCancelled else { return }
            scanTask = nil
            // The user switched apps during the search: these areas belong to a
            // window that is no longer in front.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                logger.info("App changed while searching scroll areas; not entering scroll mode")
                return
            }
            guard !found.isEmpty else {
                logger.notice("No scroll area in \(appName, privacy: .public)")
                return
            }
            targets = found
            isActive = true
            input = ScrollInput()
            guard setActiveArea(0) else {
                logger.error("Scroll mode could not receive keys; leaving it")
                return deactivate()
            }
            startListening()
            let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
            logger.info("Scroll mode in \(appName, privacy: .public): \(found.count) areas, ready after \(milliseconds) ms")
        }
    }

    private static func screenFramesInAXCoordinates() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.map { ScreenGeometry.axRect(fromAppKit: $0.frame, primaryScreenHeight: primaryHeight) }
    }

    @discardableResult
    private func setActiveArea(_ index: Int) -> Bool {
        stopScrolling()
        activeIndex = index
        let target = targets[index]
        let receivesKeys = overlay.showOutline(target.area.frame)
        if let control = target.control {
            // Scroll bars are driven directly, so the pointer stays free.
            output = .accessibility(control)
        } else {
            useWheel(for: target.area)
        }
        return receivesKeys
    }

    /// Wheel events go to whatever is under the pointer, so it moves onto the area.
    private func useWheel(for area: ScrollArea<AXNode>) {
        output = .wheel
        if originalPointer == nil {
            originalPointer = Pointer.location
        }
        Pointer.move(to: CGPoint(x: area.frame.midX, y: area.frame.midY))
    }

    /// The app stopped accepting scroll bar writes: continue with wheel events,
    /// including a scroll the user is still holding.
    private func fallBackToWheel(after failed: AXScrollControl) {
        // A late report about an area the user already left with Tab is stale.
        guard isActive, case .accessibility(let current) = output, current == failed else { return }
        logger.notice("Accessibility scrolling failed; using wheel events for this area")
        targets[activeIndex].control = nil
        useWheel(for: targets[activeIndex].area)
        if let heldCommand {
            start(heldCommand)
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
            scroller.startSmooth(direction, via: output)
        case .halfPage(let direction):
            scroller.startHalfPage(direction, in: targets[activeIndex].area.frame, via: output)
        default:
            break
        }
    }

    private func stopScrolling() {
        scroller.stop()
        heldKeyCode = nil
        heldCommand = nil
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Holding a key scrolls until key up; auto-repeat must not restart it.
        guard !event.isARepeat, let key = Self.scrollKey(for: event) else { return }
        // ⌘J or ⌃D are app shortcuts, not scroll commands.
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return }
        sequenceTimeout?.cancel()
        switch input.handle(key) {
        case .command(.scroll(let direction)):
            startHeld(.scroll(direction), keyCode: event.keyCode)
        case .command(.halfPage(let direction)):
            startHeld(.halfPage(direction), keyCode: event.keyCode)
        case .command(.top):
            scroller.scrollToEdge(top: true, via: output)
        case .command(.bottom):
            scroller.scrollToEdge(top: false, via: output)
        case .command(.nextArea):
            setActiveArea((activeIndex + 1) % targets.count)
        case .command(.exit):
            deactivate()
        case .pending:
            sequenceTimeout = Task {
                try? await Task.sleep(for: Self.sequenceDelay)
                guard !Task.isCancelled else { return }
                input.reset()
            }
        case .ignored:
            break
        }
    }

    private static func scrollKey(for event: NSEvent) -> ScrollKey? {
        switch event.keyCode {
        case KeyCode.escape: .escape
        case KeyCode.tab: .tab
        // Only Shift decides the case, never Caps Lock (`G` vs `g`).
        default: event.charactersIgnoringModifiers?.first.map {
            ScrollKey.decode($0, shift: event.modifierFlags.contains(.shift))
        }
        }
    }

    private func startListening() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            if event.type == .keyDown {
                self?.handleKeyDown(event)
            } else if event.keyCode == self?.heldKeyCode {
                // Only releasing the key that started the scroll stops it.
                self?.stopScrolling()
            }
            // Swallow every key while scroll mode is active.
            return nil
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deactivate() }
        }
        observeKeyLoss()
    }

    /// A click on the target window takes the keyboard away without an app
    /// switch. Key-up events would then never arrive and a held direction
    /// would scroll forever, so scroll mode exits instead.
    private func observeKeyLoss() {
        keyLossObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, self.isActive, self.overlay.isOverlayWindow(window) else { return }
                // Tab across displays moves the keyboard to another overlay panel;
                // only leave when no overlay panel has it after this turn.
                DispatchQueue.main.async {
                    guard self.isActive, !self.overlay.hasKeyPanel else { return }
                    self.logger.info("Scroll mode lost the keyboard; leaving it")
                    self.deactivate()
                }
            }
        }
    }

    private func stopListening() {
        if let keyLossObserver {
            NotificationCenter.default.removeObserver(keyLossObserver)
        }
        keyLossObserver = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver)
        }
        keyMonitor = nil
        appSwitchObserver = nil
    }
}
