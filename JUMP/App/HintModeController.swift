import AppKit
import JumpKit
import OSLog

/// Hint mode: scans the focused window, shows a label on every actionable
/// element, and acts on the element whose label the user types.
///
/// Dismissed by the hotkey, `Esc`, a typo, or switching apps.
@Observable
final class HintModeController {
    private(set) var lastSummary: String?

    private let permission: AccessibilityPermission
    private let overlay = HintOverlay()
    private let logger = Logger(subsystem: "com.alvaldes.jump", category: "hints")

    private var scanTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private var appSwitchObserver: (any NSObjectProtocol)?
    private var hints: [Hint<AXNode>] = []
    private var input = HintInput(labels: [])

    private enum KeyCode {
        static let escape: UInt16 = 53
        static let delete: UInt16 = 51
        static let space: UInt16 = 49
    }

    init(permission: AccessibilityPermission) {
        self.permission = permission
    }

    /// Bound to the activation hotkey.
    func toggle() {
        logger.debug("Hotkey toggle (visible: \(self.overlay.isVisible))")
        if overlay.isVisible || scanTask != nil {
            dismiss()
        } else {
            activate()
        }
    }

    private func activate() {
        guard permission.isTrusted else {
            lastSummary = "Accessibility access required"
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            lastSummary = "No app to scan"
            return
        }

        let appName = app.localizedName ?? "Unknown app"
        let pid = app.processIdentifier
        scanTask = Task {
            let start = ContinuousClock.now
            let outcome = await Result { try await FocusedWindowScanner.scan(pid: pid) }
            // Dismissed while scanning; nothing to show.
            guard !Task.isCancelled else { return }
            scanTask = nil
            switch outcome {
            case .success(let result):
                present(result, appName: appName, elapsed: ContinuousClock.now - start)
            case .failure:
                lastSummary = "\(appName): no focused window"
                logger.notice("Scan of \(appName, privacy: .public) found no focused window")
            }
        }
    }

    private func present(_ result: ScanResult<AXNode>, appName: String, elapsed: Duration) {
        let hints = HintAssigner.assign(result.elements, characters: HintLabels.defaultCharacters)
        let milliseconds = Int(elapsed / .milliseconds(1))
        let truncated = result.isTruncated ? " (truncated)" : ""
        lastSummary = "\(appName): \(hints.count) hints in \(milliseconds) ms\(truncated)"
        logger.info("""
            Scanned \(appName, privacy: .public): \(hints.count) hints, \
            \(result.visitedCount) nodes visited, \(milliseconds) ms, truncated: \(result.isTruncated)
            """)

        guard let first = hints.first else { return }
        self.hints = hints
        input = HintInput(labels: hints.map(\.label))
        overlay.show(
            hints.map { HintPresentation(label: $0.label, anchor: $0.anchor, elementFrame: $0.element.frame) },
            focusPoint: CGPoint(x: first.element.frame.midX, y: first.element.frame.midY)
        )
        startListening()
    }

    private func dismiss() {
        scanTask?.cancel()
        scanTask = nil
        hints = []
        overlay.hide()
        stopListening()
    }

    private func handle(_ event: NSEvent) {
        guard let key = Self.hintKey(for: event) else { return }
        let result = input.handle(key)
        logger.debug("Key \(String(describing: key), privacy: .public) -> \(String(describing: result), privacy: .public)")
        switch result {
        case .filtering(let typed):
            overlay.filter(typed: typed)
        case .matched(let label):
            guard let hint = hints.first(where: { $0.label == label }) else { return dismiss() }
            let flags = event.modifierFlags
            let action = HintAction(shift: flags.contains(.shift), command: flags.contains(.command), option: flags.contains(.option))
            // Hide first so focus returns to the target app before it receives the action.
            dismiss()
            logger.info("Selected \(label, privacy: .public): \(String(describing: action), privacy: .public) on \(hint.element.role, privacy: .public)")
            Task { await ElementActions.perform(action, on: hint.element) }
        case .cancelled:
            dismiss()
        case .rotate:
            overlay.rotate()
        case .ignored:
            break
        }
    }

    private static func hintKey(for event: NSEvent) -> HintKey? {
        switch event.keyCode {
        case KeyCode.escape: .escape
        case KeyCode.delete: .backspace
        case KeyCode.space: .space
        default: event.charactersIgnoringModifiers?.first.map(HintKey.character)
        }
    }

    private func startListening() {
        // The overlay panel is key, so keystrokes come here instead of the target app.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            // Swallow every key while hints are visible.
            return nil
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = app?.localizedName ?? "?"
            MainActor.assumeIsolated {
                self?.logger.debug("App switch to \(name, privacy: .public) dismisses hints")
                self?.dismiss()
            }
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
