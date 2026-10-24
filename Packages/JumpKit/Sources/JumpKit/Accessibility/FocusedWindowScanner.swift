import ApplicationServices

public enum FocusedWindowScanError: Error, Equatable {
    case noFocusedWindow
}

/// Scans the focused window of an app, off the main thread.
public nonisolated enum FocusedWindowScanner {
    /// Upper bound for a single AX request to the target app, so a hung app
    /// cannot freeze JUMP (Vimac used 1 s globally).
    private static let messagingTimeout: Float = 0.25

    @concurrent
    public static func scan(
        pid: pid_t,
        scanner: ElementScanner = ElementScanner(),
        budget: Duration = .milliseconds(150)
    ) async throws -> ScanResult<AXNode> {
        let deadline = ContinuousClock.now.advanced(by: budget)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)

        // Reading any attribute wakes Chromium's lazily built accessibility tree (Vimac trick).
        let _: String? = AXNode.copyAttribute("AXRole", of: app)

        guard let window: AXUIElement = AXNode.copyAttribute("AXFocusedWindow", of: app) else {
            throw FocusedWindowScanError.noFocusedWindow
        }
        return scanner.scan(root: AXNode(window), deadline: deadline)
    }
}
