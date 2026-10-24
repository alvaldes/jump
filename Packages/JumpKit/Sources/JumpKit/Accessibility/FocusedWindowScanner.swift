import ApplicationServices

public enum FocusedWindowScanError: Error, Equatable {
    case noFocusedWindow
}

/// Scans the focused window of an app, off the main thread.
public nonisolated enum FocusedWindowScanner {
    /// The first accessibility call of the process sets up its connection to
    /// the AX system (~15-20 ms). Doing a cheap one at launch moves that cost
    /// out of the first hotkey press.
    @concurrent
    public static func warmUp() async {
        let _: AXUIElement? = AXNode.copyAttribute("AXFocusedApplication", of: AXUIElementCreateSystemWide())
    }

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

    /// The focused window's scroll areas, largest first, the window last.
    @concurrent
    public static func scrollAreas(
        pid: pid_t,
        budget: Duration = .milliseconds(150)
    ) async throws -> [ScrollArea<AXNode>] {
        let deadline = ContinuousClock.now.advanced(by: budget)
        let app = AXNode(AXUIElementCreateApplication(pid))
        guard let window: AXUIElement = AXNode.copyAttribute("AXFocusedWindow", of: app.element) else {
            throw FocusedWindowScanError.noFocusedWindow
        }
        return ScrollAreaFinder().find(in: AXNode(window), deadline: deadline)
    }
}
