import ApplicationServices

/// Whether focus left the window a mode acts on.
nonisolated enum WindowFocusChange {
    /// Only another window counts: the overlay taking the keyboard can leave
    /// the app without a focused window for a moment, and without a window
    /// at start there is nothing to compare against.
    static func leftTarget<Window: Equatable>(initial: Window?, current: Window?) -> Bool {
        guard let initial, let current else { return false }
        return current != initial
    }
}

/// Watches the target app through the accessibility API: another of its
/// windows taking focus (⌘`, AeroSpace raising a window of the same app),
/// the app deactivating, or the app being hidden.
public final class AXWindowFocusObserver: WindowFocusObserving {
    private static let windowNotifications = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification]
    private static let leaveNotifications = [kAXApplicationDeactivatedNotification, kAXApplicationHiddenNotification]
    /// Reads run on the main thread; a busy app must not stall it.
    private static let messagingTimeout: Float = 0.1

    private var observer: AXObserver?
    private var app: AXUIElement?
    private var initialWindow: AXUIElement?
    private var onFocusLeft: (() -> Void)?

    public init() {}

    // The callback holds an unretained reference to this object.
    isolated deinit {
        stop()
    }

    public func start(pid: pid_t, onFocusLeft: @escaping () -> Void) {
        stop()
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications + Self.leaveNotifications {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        self.app = app
        self.onFocusLeft = onFocusLeft
        initialWindow = focusedWindow()
    }

    public func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        app = nil
        initialWindow = nil
        onFocusLeft = nil
    }

    private func focusedWindow() -> AXUIElement? {
        guard let app else { return nil }
        return AXNode.copyAttribute(kAXFocusedWindowAttribute, of: app)
    }

    private func handle(_ notification: String) {
        guard let onFocusLeft else { return }
        if Self.leaveNotifications.contains(notification)
            || WindowFocusChange.leftTarget(initial: initialWindow, current: focusedWindow()) {
            onFocusLeft()
        }
    }

    // Delivered on the main run loop, where the observer's source was added.
    private static let callback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let name = notification as String
        nonisolated(unsafe) let pointer = refcon
        MainActor.assumeIsolated {
            Unmanaged<AXWindowFocusObserver>.fromOpaque(pointer).takeUnretainedValue().handle(name)
        }
    }
}
