import ApplicationServices

/// Turns on the accessibility tree of Chromium and Electron apps, which only
/// build it when an assistive app asks, and turns it off again on quit.
public final class WebAccessibilityEnabler {
    /// Sets a boolean attribute on an app; returns whether the app accepted it.
    public typealias AttributeSetter = @Sendable (_ pid: pid_t, _ attribute: String, _ value: Bool) -> Bool
    /// Reads a boolean attribute; `nil` when the app does not expose it.
    public typealias AttributeReader = @Sendable (_ pid: pid_t, _ attribute: String) -> Bool?

    /// Electron's switch, also honored by current Chromium. Harmless elsewhere:
    /// apps that do not know it reject the write.
    nonisolated static let manualAccessibility = "AXManualAccessibility"

    /// The VoiceOver switch. It also changes window behavior (animations,
    /// window managers), so it is only used for browsers that need it.
    nonisolated static let enhancedUserInterface = "AXEnhancedUserInterface"

    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "company.thebrowser.Browser",
    ]

    private let setAttribute: AttributeSetter
    private let readAttribute: AttributeReader
    /// Every app seen, with the attribute JUMP turned on (if any).
    private var handled: [pid_t: String?] = [:]

    public init(
        setAttribute: @escaping AttributeSetter = WebAccessibilityEnabler.liveSetter,
        readAttribute: @escaping AttributeReader = WebAccessibilityEnabler.liveReader
    ) {
        self.setAttribute = setAttribute
        self.readAttribute = readAttribute
    }

    /// Enables the app's accessibility tree once per process. Call when an app
    /// becomes active, so the tree is built before the user asks for hints.
    /// The writes go to another process and run off the main thread, so a hung
    /// app cannot stall JUMP.
    public func enable(pid: pid_t, bundleIdentifier: String?) async {
        guard handled[pid] == nil else { return }
        handled[pid] = .some(nil)  // Claimed now, so concurrent activations do not repeat the work.
        let isChromiumBrowser = bundleIdentifier.map(Self.chromiumBrowsers.contains) ?? false
        let turnedOn = await Self.turnOn(pid: pid, isChromiumBrowser: isChromiumBrowser,
                                         set: setAttribute, read: readAttribute)
        // The app may have quit (and been forgotten) while the writes ran.
        if handled.keys.contains(pid) {
            handled[pid] = turnedOn
        }
    }

    /// Returns the attribute JUMP switched on, if any.
    @concurrent
    private static func turnOn(pid: pid_t, isChromiumBrowser: Bool,
                               set: AttributeSetter, read: AttributeReader) async -> String? {
        if set(pid, manualAccessibility, true) {
            return manualAccessibility
        }
        guard isChromiumBrowser else { return nil }
        // Already on means VoiceOver or another assistive app owns it: leave it alone.
        if read(pid, enhancedUserInterface) == true { return nil }
        return set(pid, enhancedUserInterface, true) ? enhancedUserInterface : nil
    }

    /// Drops an app that quit, so a later process reusing its pid is handled
    /// fresh and never restored by mistake.
    public func forget(pid: pid_t) {
        handled[pid] = nil
    }

    /// Restores every app JUMP changed. Call when JUMP quits; runs synchronously
    /// because the process is about to exit.
    public func restoreAll() {
        for case let (pid, attribute?) in handled {
            _ = setAttribute(pid, attribute, false)
        }
        handled.removeAll()
    }

    public static let liveSetter: AttributeSetter = { pid, attribute, value in
        // AXNode bounds the request with the messaging timeout, so a hung app cannot block JUMP for long.
        let app = AXNode(AXUIElementCreateApplication(pid))
        let flag = value ? kCFBooleanTrue! : kCFBooleanFalse!
        return AXUIElementSetAttributeValue(app.element, attribute as CFString, flag) == .success
    }

    public static let liveReader: AttributeReader = { pid, attribute in
        let app = AXNode(AXUIElementCreateApplication(pid))
        let value: Bool? = AXNode.copyAttribute(attribute, of: app.element)
        return value
    }
}
