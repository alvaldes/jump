import JumpKit
import SwiftUI

/// Items of the menu bar dropdown.
struct MenuContent: View {
    let permission: AccessibilityPermission

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if permission.isTrusted {
            Text("Accessibility access granted")
        } else {
            Button("Grant Accessibility Access…") {
                openWindow(id: OnboardingView.windowID)
                NSApp.activate()
            }
        }

        Divider()

        Button("Quit JUMP") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
