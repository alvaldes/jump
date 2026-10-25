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
    /// Another app came to the front.
    public var otherAppActivated: () -> Void
    /// The overlay lost the keyboard without an app switch (e.g. a click in
    /// the target window); keys would no longer reach the mode.
    public var keyboardLost: () -> Void

    public init(
        keyDown: @escaping (KeyPress) -> Void,
        keyUp: @escaping (UInt16) -> Void = { _ in },
        otherAppActivated: @escaping () -> Void,
        keyboardLost: @escaping () -> Void
    ) {
        self.keyDown = keyDown
        self.keyUp = keyUp
        self.otherAppActivated = otherAppActivated
        self.keyboardLost = keyboardLost
    }
}

/// Delivers keys and app events to the active mode.
public protocol ModeInputSource: AnyObject {
    func start(_ handler: ModeInputHandler)
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

/// Live input: a local key monitor (the overlay panel is key, so keys arrive
/// here instead of the target app), app activations, and overlay key loss.
public final class AppKitModeInput: ModeInputSource {
    private let overlay: HintOverlay
    private var keyMonitor: Any?
    private var appSwitchObserver: (any NSObjectProtocol)?
    private var keyLossObserver: (any NSObjectProtocol)?
    /// Bumped on every start and stop, so a deferred key-loss check from an
    /// earlier session cannot end a newer one.
    private var session = 0

    public init(overlay: HintOverlay) {
        self.overlay = overlay
    }

    public func start(_ handler: ModeInputHandler) {
        stop()
        session += 1
        let thisSession = session
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            if event.type == .keyDown {
                handler.keyDown(KeyPress(event))
            } else {
                handler.keyUp(event.keyCode)
            }
            // Swallow every key while a mode is active.
            return nil
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler.otherAppActivated() }
        }
        keyLossObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self, overlay] notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard overlay.isOverlayWindow(window) else { return }
                // Tab across displays moves the keyboard to another overlay
                // panel; only report a loss when none has it after this turn.
                DispatchQueue.main.async {
                    guard self?.session == thisSession, !overlay.hasKeyPanel else { return }
                    handler.keyboardLost()
                }
            }
        }
    }

    public func stop() {
        session += 1
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver)
        }
        if let keyLossObserver {
            NotificationCenter.default.removeObserver(keyLossObserver)
        }
        keyMonitor = nil
        appSwitchObserver = nil
        keyLossObserver = nil
    }
}
