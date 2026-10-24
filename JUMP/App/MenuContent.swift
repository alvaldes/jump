import JumpKit
import SwiftUI

/// Items of the menu bar dropdown.
struct MenuContent: View {
    let permission: AccessibilityPermission
    let hintMode: HintModeController

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if permission.isTrusted {
            Text("Accessibility access granted")
            Text(hintMode.lastSummary.map { "Last scan: \($0)" } ?? "Press ⌘⇧Space to show hints")
        } else {
            Button("Grant Accessibility Access…") {
                openWindow(id: OnboardingView.windowID)
                NSApp.activate()
            }
        }

        Divider()

        Button("Settings…") {
            // A menu bar agent is not active; bring the window to the front.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit JUMP") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
