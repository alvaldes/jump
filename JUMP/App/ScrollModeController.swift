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
    private var keyMonitor: Any?
    private var appSwitchObserver: (any NSObjectProtocol)?

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
        scroller.stop()
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
        scanTask = Task {
            let found = (try? await FocusedWindowScanner.scrollAreas(pid: pid)) ?? []
            guard !Task.isCancelled else { return }
            scanTask = nil
            guard !found.isEmpty else {
                logger.notice("No scroll area in \(appName, privacy: .public)")
                return
            }
            areas = found
            isActive = true
            input = ScrollInput()
            originalPointer = Pointer.location
            setActiveArea(0)
            startListening()
            let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
            logger.info("Scroll mode in \(appName, privacy: .public): \(found.count) areas, ready after \(milliseconds) ms")
        }
    }

    private func setActiveArea(_ index: Int) {
        scroller.stop()
        activeIndex = index
        let frame = areas[index].frame
        overlay.showOutline(frame)
        // Scroll events go to whatever is under the pointer.
        Pointer.move(to: CGPoint(x: frame.midX, y: frame.midY))
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Holding a key scrolls until key up; auto-repeat must not restart it.
        guard !event.isARepeat, let key = Self.scrollKey(for: event) else { return }
        sequenceTimeout?.cancel()
        switch input.handle(key) {
        case .command(.scroll(let direction)):
            scroller.startSmooth(direction)
        case .command(.halfPage(let direction)):
            scroller.startHalfPage(direction, in: areas[activeIndex].frame)
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
            } else {
                self?.scroller.stop()
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
    }

    private func stopListening() {
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
