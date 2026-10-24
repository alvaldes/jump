import AppKit
import JumpKit
import OSLog

/// Hint mode: scans the focused window and shows a label on every actionable element.
///
/// Dismissed by the hotkey, `Esc`, or switching apps. Typing a label to act on
/// its element arrives in roadmap step 4.
@Observable
final class HintModeController {
    private(set) var lastSummary: String?

    private let permission: AccessibilityPermission
    private let overlay = HintOverlay()
    private let logger = Logger(subsystem: "com.alvaldes.jump", category: "hints")

    private var scanTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private var appSwitchObserver: (any NSObjectProtocol)?

    private static let escapeKeyCode: UInt16 = 53

    init(permission: AccessibilityPermission) {
        self.permission = permission
    }

    /// Bound to the activation hotkey.
    func toggle() {
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
        overlay.show(
            hints.map { HintPresentation(label: $0.label, anchor: $0.anchor) },
            focusPoint: CGPoint(x: first.element.frame.midX, y: first.element.frame.midY)
        )
        startListening()
    }

    private func dismiss() {
        scanTask?.cancel()
        scanTask = nil
        overlay.hide()
        stopListening()
    }

    private func startListening() {
        // The overlay panel is key, so keystrokes come here instead of the target app.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == Self.escapeKeyCode {
                self?.dismiss()
            }
            // Swallow every key while hints are visible (labels are handled in step 4).
            return nil
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
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
