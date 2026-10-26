import AppKit
import JumpKit
import KeyboardShortcuts

/// App-wide work that is not part of a mode: warm-ups at launch, display
/// changes, Chromium/Electron accessibility for the frontmost app, and
/// turning the shortcuts off in excluded apps.
final class AppServices {
    let webAccessibility = WebAccessibilityEnabler()

    private let permission: AccessibilityPermission
    private let settings: JumpSettings
    private let overlay: HintOverlay
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    init(permission: AccessibilityPermission, settings: JumpSettings, overlay: HintOverlay) {
        self.permission = permission
        self.settings = settings
        self.overlay = overlay
        overlay.prepare()
        if permission.isTrusted {
            Task { await FocusedWindowScanner.warmUp() }
        }
        observe()
        applyExclusion(to: NSWorkspace.shared.frontmostApplication)
    }

    /// While an excluded app is in front JUMP's shortcuts are unregistered,
    /// so those keys reach the app as if JUMP were not running.
    private func applyExclusion(to app: NSRunningApplication?) {
        KeyboardShortcuts.isEnabled = !settings.isExcluded(bundleIdentifier: app?.bundleIdentifier)
    }

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        let app = NotificationCenter.default

        add(app, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.overlay.prepare()
        }
        // Chromium and Electron build their accessibility tree only on request
        // and asynchronously, so it is requested as soon as an app comes to the
        // front, well before the hotkey.
        add(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] notification in
            self?.applyExclusion(to: Self.runningApp(notification))
        }
        add(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] notification in
            guard let self, self.permission.isTrusted, let running = Self.runningApp(notification),
                  running.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            let pid = running.processIdentifier
            let bundleIdentifier = running.bundleIdentifier
            Task { await self.webAccessibility.enable(pid: pid, bundleIdentifier: bundleIdentifier) }
        }
        add(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] notification in
            guard let pid = Self.runningApp(notification)?.processIdentifier else { return }
            self?.webAccessibility.forget(pid: pid)
        }
        add(app, NSApplication.willTerminateNotification) { [weak self] _ in
            self?.webAccessibility.restoreAll()
        }
    }

    private func add(_ center: NotificationCenter, _ name: Notification.Name,
                     _ handler: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            nonisolated(unsafe) let notification = notification
            MainActor.assumeIsolated { handler(notification) }
        }
        observers.append((center, token))
    }

    private nonisolated static func runningApp(_ notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }
}
