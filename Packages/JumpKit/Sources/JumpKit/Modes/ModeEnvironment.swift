import AppKit

// The system boundaries of hint and scroll mode, as protocols, so the modes'
// lifecycle can be tested without AppKit, the window server or real apps.

/// A key event while a mode is active, decoded from `NSEvent`.
public nonisolated struct KeyPress: Sendable, Equatable {
    public var keyCode: UInt16
    /// Typed characters ignoring modifiers (Caps Lock may still uppercase them).
    public var characters: String
    public var shift = false
    public var command = false
    public var option = false
    public var control = false
    public var isRepeat = false

    public init(keyCode: UInt16, characters: String, shift: Bool = false, command: Bool = false,
                option: Bool = false, control: Bool = false, isRepeat: Bool = false) {
        self.keyCode = keyCode
        self.characters = characters
        self.shift = shift
        self.command = command
        self.option = option
        self.control = control
        self.isRepeat = isRepeat
    }

    /// ⌘, ⌃ or ⌥ held: an app shortcut, not a mode command.
    public var isShortcut: Bool { command || control || option }

    enum KeyCode {
        static let escape: UInt16 = 53
        static let delete: UInt16 = 51
        static let space: UInt16 = 49
        static let tab: UInt16 = 48
    }
}

extension KeyPress {
    public init(_ event: NSEvent) {
        let flags = event.modifierFlags
        self.init(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers ?? "",
            shift: flags.contains(.shift),
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            isRepeat: event.isARepeat
        )
    }
}

extension HintKey {
    public init?(_ press: KeyPress) {
        switch press.keyCode {
        case KeyPress.KeyCode.escape: self = .escape
        case KeyPress.KeyCode.delete: self = .backspace
        case KeyPress.KeyCode.space: self = .space
        default:
            guard let character = press.characters.first else { return nil }
            self = .character(character)
        }
    }
}

extension ScrollKey {
    public init?(_ press: KeyPress) {
        switch press.keyCode {
        case KeyPress.KeyCode.escape: self = .escape
        case KeyPress.KeyCode.tab: self = .tab
        default:
            // Only Shift decides the case, never Caps Lock (`G` vs `g`).
            guard let character = press.characters.first else { return nil }
            self = ScrollKey.decode(character, shift: press.shift)
        }
    }
}

/// What a mode reacts to while it is active.
public struct ModeInputHandler {
    public var keyDown: (KeyPress) -> Void
    public var keyUp: (_ keyCode: UInt16) -> Void
    /// The user moved focus away from the target window, with the mouse or
    /// the keyboard: another app came to the front, or another window of the
    /// target app took focus (⌘\`, a window manager such as AeroSpace).
    public var focusLeft: () -> Void
    /// The overlay lost the keyboard without an app switch (e.g. a click in
    /// the target window); keys would no longer reach the mode.
    public var keyboardLost: () -> Void

    public init(
        keyDown: @escaping (KeyPress) -> Void,
        keyUp: @escaping (UInt16) -> Void = { _ in },
        focusLeft: @escaping () -> Void,
        keyboardLost: @escaping () -> Void
    ) {
        self.keyDown = keyDown
        self.keyUp = keyUp
        self.focusLeft = focusLeft
        self.keyboardLost = keyboardLost
    }
}

/// Delivers keys and focus events to the active mode.
public protocol ModeInputSource: AnyObject {
    /// - Parameter target: The app the mode acts on; focus leaving its
    ///   window ends the mode.
    func start(_ handler: ModeInputHandler, target: FrontmostApp)
    func stop()
}

/// The hint/outline overlay.
public protocol OverlayPresenting: AnyObject {
    var isVisible: Bool { get }
    func show(_ hints: [HintPresentation], focusPoint: CGPoint?)
    /// Returns whether the overlay could take the keyboard.
    @discardableResult func showOutline(_ frame: CGRect) -> Bool
    func filter(typed: String)
    func rotate()
    func hide()
}

extension HintOverlay: OverlayPresenting {}

public protocol PointerControlling {
    var location: CGPoint { get }
    func move(to point: CGPoint)
}

public struct SystemPointer: PointerControlling {
    public init() {}
    public var location: CGPoint { Pointer.location }
    public func move(to point: CGPoint) { Pointer.move(to: point) }
}

/// The app a mode acts on.
public nonisolated struct FrontmostApp: Sendable, Equatable {
    public let pid: pid_t
    public let name: String
    public let bundleIdentifier: String?

    public init(pid: pid_t, name: String, bundleIdentifier: String?) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    /// The frontmost app, or `nil` when it is JUMP itself.
    public static func current() -> FrontmostApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return FrontmostApp(pid: app.processIdentifier, name: app.localizedName ?? "Unknown app",
                            bundleIdentifier: app.bundleIdentifier)
    }
}

/// What `AppKitModeInput` needs from the overlay.
public protocol OverlayKeyboard: AnyObject {
    /// Whether one of the overlay panels currently receives the keyboard.
    var hasKeyPanel: Bool { get }
    func isOverlayWindow(_ object: Any?) -> Bool
}

extension HintOverlay: OverlayKeyboard {}

/// Watches one app for focus leaving the window that was focused at start.
public protocol WindowFocusObserving: AnyObject {
    func start(pid: pid_t, onFocusLeft: @escaping () -> Void)
    func stop()
}

/// Adds and removes a local key monitor (`NSEvent`'s, in the app).
public struct KeyEventMonitor {
    public var add: (_ handler: @escaping (NSEvent) -> NSEvent?) -> Any?
    public var remove: (_ monitor: Any) -> Void

    public init(add: @escaping (@escaping (NSEvent) -> NSEvent?) -> Any?, remove: @escaping (Any) -> Void) {
        self.add = add
        self.remove = remove
    }

    public static let local = KeyEventMonitor(
        add: { handler in NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp], handler: handler) },
        remove: { NSEvent.removeMonitor($0) }
    )
}

/// Live input: a local key monitor (the overlay panel is key, so keys arrive
/// here instead of the target app), focus leaving the target window, and
/// overlay key loss.
///
/// The overlay panel is non-activating, so a focus change that stays inside
/// the target app (⌘\`, AeroSpace) neither activates an app nor takes the
/// keyboard from the panel; only watching the target app's windows sees it.
public final class AppKitModeInput: ModeInputSource {
    private let overlay: OverlayKeyboard
    private let windowFocus: WindowFocusObserving
    private let keyEvents: KeyEventMonitor
    private let workspaceCenter: NotificationCenter
    private let windowCenter: NotificationCenter
    private var keyMonitor: Any?
    private var appSwitchObserver: (any NSObjectProtocol)?
    private var keyLossObserver: (any NSObjectProtocol)?
    /// Bumped on every start and stop, so a deferred key-loss check or a late
    /// focus report from an earlier session cannot end a newer one.
    private var session = 0

    public init(
        overlay: OverlayKeyboard,
        windowFocus: WindowFocusObserving = AXWindowFocusObserver(),
        keyMonitor: KeyEventMonitor = .local,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        windowCenter: NotificationCenter = .default
    ) {
        self.overlay = overlay
        self.windowFocus = windowFocus
        self.keyEvents = keyMonitor
        self.workspaceCenter = workspaceCenter
        self.windowCenter = windowCenter
    }

    public func start(_ handler: ModeInputHandler, target: FrontmostApp) {
        stop()
        session += 1
        let thisSession = session
        keyMonitor = keyEvents.add { event in
            if event.type == .keyDown {
                handler.keyDown(KeyPress(event))
            } else {
                handler.keyUp(event.keyCode)
            }
            // Swallow every key while a mode is active.
            return nil
        }
        appSwitchObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler.focusLeft() }
        }
        windowFocus.start(pid: target.pid) { [weak self] in
            guard self?.session == thisSession else { return }
            handler.focusLeft()
        }
        keyLossObserver = windowCenter.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            nonisolated(unsafe) let window = notification.object
            MainActor.assumeIsolated {
                guard self?.overlay.isOverlayWindow(window) == true else { return }
                // Tab across displays moves the keyboard to another overlay
                // panel; only report a loss when none has it after this turn.
                DispatchQueue.main.async {
                    guard let self, self.session == thisSession, !self.overlay.hasKeyPanel else { return }
                    handler.keyboardLost()
                }
            }
        }
    }

    public func stop() {
        session += 1
        if let keyMonitor {
            keyEvents.remove(keyMonitor)
        }
        if let appSwitchObserver {
            workspaceCenter.removeObserver(appSwitchObserver)
        }
        if let keyLossObserver {
            windowCenter.removeObserver(keyLossObserver)
        }
        windowFocus.stop()
        keyMonitor = nil
        appSwitchObserver = nil
        keyLossObserver = nil
    }
}
