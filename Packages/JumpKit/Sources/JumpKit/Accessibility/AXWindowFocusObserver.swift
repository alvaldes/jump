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
    private nonisolated static let windowNotifications = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification]
    private nonisolated static let leaveNotifications = [kAXApplicationDeactivatedNotification, kAXApplicationHiddenNotification]
    /// Reads after registration run on the main thread; a busy app must not stall it.
    private nonisolated static let messagingTimeout: Float = 0.1

    private var observer: AXObserver?
    private var app: AXUIElement?
    private var initialWindow: AXUIElement?
    private var onFocusLeft: (() -> Void)?
    /// Bumped on every start and stop, so a registration that finishes after
    /// the mode ended (or restarted) is dropped.
    private var generation = 0

    public init() {}

    // The callback holds an unretained reference to this object.
    isolated deinit {
        stop()
    }

    /// Registering with the app takes 100-180 ms right after the overlay takes
    /// the keyboard, so it runs off the main thread: hints appear first, and
    /// app switches are still caught by the workspace notification meanwhile.
    public func start(pid: pid_t, onFocusLeft: @escaping () -> Void) {
        stop()
        let generation = generation
        self.onFocusLeft = onFocusLeft
        nonisolated(unsafe) let refcon = Unmanaged.passUnretained(self).toOpaque()
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let registration = Self.register(pid: pid, refcon: refcon) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(registration.observer), .commonModes)
                observer = registration.observer
                app = registration.app
                initialWindow = registration.initialWindow
            }
        }
    }

    private nonisolated struct Registration: @unchecked Sendable {
        let observer: AXObserver
        let app: AXUIElement
        let initialWindow: AXUIElement?
    }

    private nonisolated static func register(pid: pid_t, refcon: UnsafeMutableRawPointer) -> Registration? {
        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        for name in windowNotifications + leaveNotifications {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        let window: AXUIElement? = AXNode.copyAttribute(kAXFocusedWindowAttribute, of: app)
        return Registration(observer: created, app: app, initialWindow: window)
    }

    public func stop() {
        generation += 1
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

    /// The notified element is the window that took focus. Reading the
    /// focused window instead is not enough: Finder reports none for a moment
    /// right after another of its windows takes focus.
    private func handle(_ notification: String, element: AXUIElement) {
        guard let onFocusLeft else { return }
        if Self.leaveNotifications.contains(notification)
            || WindowFocusChange.leftTarget(initial: initialWindow, current: window(notifiedBy: element)) {
            onFocusLeft()
        }
    }

    private func window(notifiedBy element: AXUIElement) -> AXUIElement? {
        let role: String? = AXNode.copyAttribute(kAXRoleAttribute, of: element)
        return role == kAXWindowRole ? element : focusedWindow()
    }

    // Delivered on the main run loop, where the observer's source was added.
    private nonisolated static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let name = notification as String
        nonisolated(unsafe) let pointer = refcon
        nonisolated(unsafe) let element = element
        MainActor.assumeIsolated {
            Unmanaged<AXWindowFocusObserver>.fromOpaque(pointer).takeUnretainedValue()
                .handle(name, element: element)
        }
    }
}
