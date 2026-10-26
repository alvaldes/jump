import os
import SwiftUI

/// Opens Settings in front: from the menu and from ⌘, inside a mode.
///
/// SwiftUI only hands out `openSettings` to views, so the always-present menu
/// bar label lends it here.
@MainActor
final class SettingsOpener {
    private static let logger = Logger(subsystem: "com.alvaldes.jump", category: "settings")

    fileprivate var action: OpenSettingsAction?

    func open() {
        // A menu bar agent is not active; bring the window to the front.
        NSApp.activate()
        action?()
        // From a mode the overlay panel never activated JUMP, so the window
        // SwiftUI just created can stay behind the target app; it exists on
        // the next turn.
        DispatchQueue.main.async {
            // SwiftUI names it com_apple_SwiftUI_Settings_window; any other
            // visible window that is not an overlay panel is the fallback.
            let windows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
            let window = windows.first(where: { $0.identifier?.rawValue.contains("Settings") == true })
                ?? windows.first
            if !NSApp.isActive {
                // Cooperative activation can refuse a background agent.
                NSApp.activate(ignoringOtherApps: true)
            }
            window?.makeKeyAndOrderFront(nil)
            Self.logger.info("""
                Settings window \(window?.identifier?.rawValue ?? "none", privacy: .public), \
                active \(NSApp.isActive), key \(window?.isKeyWindow ?? false)
                """)
        }
    }
}

/// The menu bar icon, which also hands its `openSettings` to `SettingsOpener`.
struct MenuBarLabel: View {
    let imageName: String
    let opener: SettingsOpener

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(imageName)
            .accessibilityLabel("JUMP")
            .onAppear { opener.action = openSettings }
    }
}
