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
    private let settings: JumpSettings
    private let overlay = HintOverlay()
    private let webAccessibility = WebAccessibilityEnabler()
    private let logger = Logger(subsystem: "com.alvaldes.jump", category: "hints")

    private var scanTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private var appSwitchObserver: (any NSObjectProtocol)?
    private var screenObserver: (any NSObjectProtocol)?
    private var activationObserver: (any NSObjectProtocol)?
    private var terminationObserver: (any NSObjectProtocol)?
    private var appQuitObserver: (any NSObjectProtocol)?
    private var hints: [Hint<AXNode>] = []
    private var input = HintInput(labels: [])

    private enum KeyCode {
        static let escape: UInt16 = 53
        static let delete: UInt16 = 51
        static let space: UInt16 = 49
    }

    init(permission: AccessibilityPermission, settings: JumpSettings) {
        self.permission = permission
        self.settings = settings
        overlay.prepare()
        if permission.isTrusted {
            Task { await FocusedWindowScanner.warmUp() }
        }
        observeAppLifecycle()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.overlay.prepare() }
        }
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
        let bundleIdentifier = app.bundleIdentifier
        // Latency budget (spec §3.9) is measured from the hotkey to hints on screen.
        let start = ContinuousClock.now
        scanTask = Task {
            // Usually already done on activation; covers apps that were in front before JUMP started.
            await webAccessibility.enable(pid: pid, bundleIdentifier: bundleIdentifier)
            let outcome = await Result { try await FocusedWindowScanner.scan(pid: pid) }
            // Dismissed while scanning; nothing to show.
            guard !Task.isCancelled else { return }
            scanTask = nil
            switch outcome {
            case .success(let result):
                present(result, appName: appName, start: start)
            case .failure:
                lastSummary = "\(appName): no focused window"
                logger.notice("Scan of \(appName, privacy: .public) found no focused window")
            }
        }
    }

    private func present(_ result: ScanResult<AXNode>, appName: String, start: ContinuousClock.Instant) {
        let scanned = ContinuousClock.now
        let hints = HintAssigner.assign(result.elements, characters: settings.hintCharacters)
        if let first = hints.first {
            self.hints = hints
            input = HintInput(labels: hints.map(\.label))
            overlay.show(
                hints.map { HintPresentation(label: $0.label, anchor: $0.anchor, elementFrame: $0.element.frame) },
                focusPoint: CGPoint(x: first.element.frame.midX, y: first.element.frame.midY)
            )
            startListening()
        }

        let totalMs = Int((ContinuousClock.now - start) / .milliseconds(1))
        let scanMs = Int((scanned - start) / .milliseconds(1))
        let truncated = result.isTruncated ? " (truncated)" : ""
        lastSummary = "\(appName): \(hints.count) hints in \(totalMs) ms\(truncated)"
        logger.info("""
            Hints for \(appName, privacy: .public): \(hints.count) hints, \(result.visitedCount) nodes, \
            scan \(scanMs) ms, on screen after \(totalMs) ms, truncated: \(result.isTruncated)
            """)
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

    /// Chromium and Electron build their accessibility tree only on request and
    /// asynchronously, so it is requested as soon as an app comes to the front,
    /// well before the hotkey. Restored when JUMP quits.
    private func observeAppLifecycle() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let pid = app?.processIdentifier, pid != ProcessInfo.processInfo.processIdentifier else { return }
            let bundleIdentifier = app?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, self.permission.isTrusted else { return }
                Task { await self.webAccessibility.enable(pid: pid, bundleIdentifier: bundleIdentifier) }
            }
        }
        appQuitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let pid = app?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.webAccessibility.forget(pid: pid) }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.webAccessibility.restoreAll() }
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
