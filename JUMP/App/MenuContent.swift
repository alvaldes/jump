import JumpKit
import KeyboardShortcuts
import SwiftUI

/// Items of the menu bar dropdown.
struct MenuContent: View {
    let permission: AccessibilityPermission
    let hintMode: LiveHintMode
    let searchMode: LiveTextSearchMode
    let settingsOpener: SettingsOpener

    @Environment(\.openWindow) private var openWindow

    /// The hint shortcut as the user set it; it can be changed or removed.
    private var hintPrompt: String {
        KeyboardShortcuts.getShortcut(for: .activateHints).map { "Press \($0) to show hints" }
            ?? "Set a shortcut in Settings to show hints"
    }

    var body: some View {
        if permission.isTrusted {
            Text("Accessibility access granted")
            Text(hintMode.lastSummary.map { "Last scan: \($0)" } ?? hintPrompt)
            if let summary = searchMode.lastSummary {
                Text("Last search: \(summary)")
            }
        } else {
            Button("Grant Accessibility Access…") {
                openWindow(id: OnboardingView.windowID)
                NSApp.activate()
            }
        }

        Divider()

        Button("Settings…") {
            settingsOpener.open()
        }
        .keyboardShortcut(",")

        Button("Quit JUMP") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
