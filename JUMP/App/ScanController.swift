import AppKit
import JumpKit
import OSLog

/// Runs a scan of the frontmost app's focused window when the hotkey fires.
///
/// Temporary surface for roadmap step 2: results are only summarized in the
/// menu and the log until the hint overlay exists (step 3).
@Observable
final class ScanController {
    private(set) var lastSummary: String?

    private let permission: AccessibilityPermission
    private let logger = Logger(subsystem: "com.alvaldes.jump", category: "scan")
    private var scanTask: Task<Void, Never>?

    init(permission: AccessibilityPermission) {
        self.permission = permission
    }

    func scanFocusedWindow() {
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
        scanTask?.cancel()
        scanTask = Task {
            let start = ContinuousClock.now
            do {
                let result = try await FocusedWindowScanner.scan(pid: pid)
                let elapsed = ContinuousClock.now - start
                report(result, appName: appName, elapsed: elapsed)
            } catch {
                lastSummary = "\(appName): no focused window"
                logger.notice("Scan of \(appName, privacy: .public) found no focused window")
            }
        }
    }

    private func report(_ result: ScanResult<AXNode>, appName: String, elapsed: Duration) {
        let milliseconds = Int(elapsed / .milliseconds(1))
        let truncated = result.isTruncated ? " (truncated)" : ""
        lastSummary = "\(appName): \(result.elements.count) elements in \(milliseconds) ms\(truncated)"
        logger.info("""
            Scanned \(appName, privacy: .public): \(result.elements.count) elements, \
            \(result.visitedCount) nodes visited, \(milliseconds) ms, truncated: \(result.isTruncated)
            """)
    }
}
