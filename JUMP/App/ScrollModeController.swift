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
    private var areas: [ScrollArea<AXNode>] = []
    private var activeIndex = 0
    private var input = ScrollInput()
    private var sequenceTimeout: Task<Void, Never>?
    /// Where the pointer was before scroll mode moved it.
    private var originalPointer: CGPoint?
    /// The direction key whose release stops the current scroll.
    private var heldKeyCode: UInt16?
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
        areas = []
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
            let found = (try? await FocusedWindowScanner.scrollAreas(pid: pid, screens: screens)) ?? []
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
            areas = found
            isActive = true
            input = ScrollInput()
            originalPointer = Pointer.location
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
        let frame = areas[index].frame
        let receivesKeys = overlay.showOutline(frame)
        // Scroll events go to whatever is under the pointer.
        Pointer.move(to: CGPoint(x: frame.midX, y: frame.midY))
        return receivesKeys
    }

    private func stopScrolling() {
        scroller.stop()
        heldKeyCode = nil
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Holding a key scrolls until key up; auto-repeat must not restart it.
        guard !event.isARepeat, let key = Self.scrollKey(for: event) else { return }
        // ⌘J or ⌃D are app shortcuts, not scroll commands.
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return }
        sequenceTimeout?.cancel()
        switch input.handle(key) {
        case .command(.scroll(let direction)):
            scroller.startSmooth(direction)
            heldKeyCode = event.keyCode
        case .command(.halfPage(let direction)):
            scroller.startHalfPage(direction, in: areas[activeIndex].frame)
            heldKeyCode = event.keyCode
        case .command(.top):
            scroller.scrollToEdge(top: true)
        case .command(.bottom):
            scroller.scrollToEdge(top: false)
        case .command(.nextArea):
            setActiveArea((activeIndex + 1) % areas.count)
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
        // `characters` keeps Shift, so `G` and `g` stay distinct.
        default: event.characters?.first.map(ScrollKey.character)
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
