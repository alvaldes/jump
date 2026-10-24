import ApplicationServices

/// Turns on the accessibility tree of Chromium and Electron apps, which only
/// build it when an assistive app asks, and turns it off again on quit.
public final class WebAccessibilityEnabler {
    /// Sets a boolean attribute on an app; returns whether the app accepted it.
    public typealias AttributeSetter = (_ pid: pid_t, _ attribute: String, _ value: Bool) -> Bool

    /// Electron's switch, also honored by current Chromium. Harmless elsewhere:
    /// apps that do not know it reject the write.
    static let manualAccessibility = "AXManualAccessibility"

    /// The VoiceOver switch. It also changes window behavior (animations,
    /// window managers), so it is only used for browsers that need it.
    static let enhancedUserInterface = "AXEnhancedUserInterface"

    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "company.thebrowser.Browser",
    ]

    private let setAttribute: AttributeSetter
    /// Every app seen, with the attribute JUMP turned on (if any).
    private var handled: [pid_t: String?] = [:]

    public init(setAttribute: @escaping AttributeSetter = WebAccessibilityEnabler.liveSetter) {
        self.setAttribute = setAttribute
    }

    /// Enables the app's accessibility tree once per process. Call when an app
    /// becomes active, so the tree is built before the user asks for hints.
    public func enable(pid: pid_t, bundleIdentifier: String?) {
        guard handled[pid] == nil else { return }
        if setAttribute(pid, Self.manualAccessibility, true) {
            handled[pid] = Self.manualAccessibility
        } else if let bundleIdentifier, Self.chromiumBrowsers.contains(bundleIdentifier),
                  setAttribute(pid, Self.enhancedUserInterface, true) {
            handled[pid] = Self.enhancedUserInterface
        } else {
            handled[pid] = .some(nil)
        }
    }

    /// Drops an app that quit, so a later process reusing its pid is handled
    /// fresh and never restored by mistake.
    public func forget(pid: pid_t) {
        handled[pid] = nil
    }

    /// Restores every app JUMP changed. Call when JUMP quits.
    public func restoreAll() {
        for case let (pid, attribute?) in handled {
            _ = setAttribute(pid, attribute, false)
        }
        handled.removeAll()
    }

    public static let liveSetter: AttributeSetter = { pid, attribute, value in
        // AXNode bounds the request with the messaging timeout, so a hung app cannot block JUMP.
        let app = AXNode(AXUIElementCreateApplication(pid))
        let flag = value ? kCFBooleanTrue! : kCFBooleanFalse!
        return AXUIElementSetAttributeValue(app.element, attribute as CFString, flag) == .success
    }
}
