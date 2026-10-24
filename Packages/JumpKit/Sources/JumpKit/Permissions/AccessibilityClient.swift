import AppKit
import ApplicationServices

/// System boundary for the Accessibility (TCC) permission.
///
/// Every interaction with the OS goes through these closures so the
/// permission logic can be tested without touching real TCC state.
public struct AccessibilityClient: Sendable {
    /// Returns whether this process is trusted, without prompting.
    public var isTrusted: @Sendable () -> Bool
    /// Shows the system prompt (if not yet trusted) and returns the current trust.
    public var requestTrust: @Sendable () -> Bool
    /// Opens System Settings > Privacy & Security > Accessibility.
    public var openSystemSettings: @Sendable () -> Void
    /// Emits whenever the system-wide Accessibility trust list may have changed.
    public var trustChanges: @Sendable () -> AsyncStream<Void>

    public init(
        isTrusted: @escaping @Sendable () -> Bool,
        requestTrust: @escaping @Sendable () -> Bool,
        openSystemSettings: @escaping @Sendable () -> Void,
        trustChanges: @escaping @Sendable () -> AsyncStream<Void>
    ) {
        self.isTrusted = isTrusted
        self.requestTrust = requestTrust
        self.openSystemSettings = openSystemSettings
        self.trustChanges = trustChanges
    }
}

extension AccessibilityClient {
    /// Value of `kAXTrustedCheckOptionPrompt`. Spelled out because the imported
    /// global is mutable state, which Swift 6 strict concurrency rejects.
    private nonisolated static let promptOptionKey = "AXTrustedCheckOptionPrompt"

    /// Posted by the system when any app's Accessibility trust changes.
    private nonisolated static let trustChangedNotification = Notification.Name("com.apple.accessibility.api")

    /// `AXIsProcessTrusted()` lags behind the notification, so re-check after a short delay.
    private nonisolated static let trustSettleDelay: Duration = .milliseconds(500)

    private nonisolated static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    public static let live = AccessibilityClient(
        isTrusted: { AXIsProcessTrusted() },
        requestTrust: {
            let options = [promptOptionKey: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        },
        openSystemSettings: {
            Task { @MainActor in NSWorkspace.shared.open(settingsURL) }
        },
        trustChanges: {
            AsyncStream { continuation in
                let observer = TrustChangeObserver(name: trustChangedNotification) {
                    Task {
                        try? await Task.sleep(for: trustSettleDelay)
                        continuation.yield()
                    }
                }
                continuation.onTermination = { _ in observer.invalidate() }
            }
        }
    )
}

/// Distributed-notification observer that keeps receiving while JUMP is inactive.
///
/// `NSApplication` suspends distributed notifications for inactive apps, and a
/// menu bar agent is inactive almost all the time. Only the selector-based API
/// accepts `.deliverImmediately`, hence this small NSObject.
private final class TrustChangeObserver: NSObject, Sendable {
    private let onChange: @Sendable () -> Void

    nonisolated init(name: Notification.Name, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handle),
            name: name,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    nonisolated func invalidate() {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc nonisolated private func handle(_ notification: Notification) {
        onChange()
    }
}
