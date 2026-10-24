import JumpKit
import SwiftUI

@main
struct JumpApp: App {
    @State private var permission: AccessibilityPermission

    init() {
        let permission = AccessibilityPermission()
        _permission = State(initialValue: permission)
        // Track grants and revocations for the whole app lifetime.
        Task { await permission.monitor() }
    }

    var body: some Scene {
        MenuBarExtra("JUMP", systemImage: "keyboard") {
            MenuContent(permission: permission)
        }

        Window("Welcome to JUMP", id: OnboardingView.windowID) {
            OnboardingView(permission: permission)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(permission.isTrusted ? .suppressed : .presented)
    }
}
