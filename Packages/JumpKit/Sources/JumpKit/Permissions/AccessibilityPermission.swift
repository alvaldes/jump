import Observation

/// Observable Accessibility permission state for the UI.
///
/// JUMP cannot read the screen's UI elements or act on them until the user
/// grants Accessibility access in System Settings.
@Observable
public final class AccessibilityPermission {
    public private(set) var isTrusted: Bool

    private let client: AccessibilityClient

    public init(client: AccessibilityClient = .live) {
        self.client = client
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
    public func monitor() async {
        for await _ in client.trustChanges() {
            refresh()
        }
    }
}
