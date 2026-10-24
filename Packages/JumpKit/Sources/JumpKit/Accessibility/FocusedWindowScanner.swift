import ApplicationServices

public enum FocusedWindowScanError: Error, Equatable {
    case noFocusedWindow
}

/// Scans the focused window of an app, off the main thread.
public nonisolated enum FocusedWindowScanner {
    @concurrent
    public static func scan(
        pid: pid_t,
        scanner: ElementScanner = ElementScanner(),
        budget: Duration = .milliseconds(150)
    ) async throws -> ScanResult<AXNode> {
        let deadline = ContinuousClock.now.advanced(by: budget)
        let app = AXNode(AXUIElementCreateApplication(pid))

        // Reading any attribute wakes Chromium's lazily built accessibility tree (Vimac trick).
        let _: String? = AXNode.copyAttribute("AXRole", of: app.element)

        guard let window: AXUIElement = AXNode.copyAttribute("AXFocusedWindow", of: app.element) else {
            throw FocusedWindowScanError.noFocusedWindow
        }
        return scanner.scan(root: AXNode(window), deadline: deadline)
    }
}
