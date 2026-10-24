import Observation

/// Observable Accessibility permission state for the UI.
///
/// JUMP cannot read the screen's UI elements or act on them until the user
/// grants Accessibility access in System Settings.
@Observable
public final class AccessibilityPermission {
    public private(set) var isTrusted: Bool

    private let client: AccessibilityClient
    private let pollInterval: Duration

    /// - Parameter pollInterval: How often to re-check while access is missing.
    ///   Polling only runs until access is granted, so idle CPU stays at zero.
    public init(client: AccessibilityClient = .live, pollInterval: Duration = .seconds(1)) {
        self.client = client
        self.pollInterval = pollInterval
        self.isTrusted = client.isTrusted()
    }

    /// Shows the system permission prompt when access is missing.
    public func request() {
        guard !isTrusted else { return }
        isTrusted = client.requestTrust()
    }

    public func openSystemSettings() {
        client.openSystemSettings()
    }

    public func refresh() {
        isTrusted = client.isTrusted()
    }

    /// Keeps `isTrusted` in sync with System Settings until the task is cancelled.
    ///
    /// Trust-change notifications are not delivered reliably while the app is
    /// inactive, so a grant is detected by polling; later revocations arrive
    /// through the notification stream.
    public func monitor() async {
        await withTaskGroup { group in
            group.addTask { await self.pollUntilTrusted() }
            group.addTask { await self.refreshOnTrustChanges() }
        }
    }

    private func pollUntilTrusted() async {
        while !isTrusted, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            refresh()
        }
    }

    private func refreshOnTrustChanges() async {
        for await _ in client.trustChanges() {
            refresh()
        }
    }
}
