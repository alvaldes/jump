import JumpKit
import KeyboardShortcuts
import SwiftUI

@main
struct JumpApp: App {
    @State private var permission: AccessibilityPermission
    @State private var hintMode: HintModeController

    init() {
        let permission = AccessibilityPermission()
        let hintMode = HintModeController(permission: permission)
        _permission = State(initialValue: permission)
        _hintMode = State(initialValue: hintMode)
        // Track grants and revocations for the whole app lifetime.
        Task { await permission.monitor() }
        KeyboardShortcuts.onKeyDown(for: .activateHints) {
            hintMode.toggle()
        }
    }

    var body: some Scene {
        MenuBarExtra("JUMP", systemImage: "keyboard") {
            MenuContent(permission: permission, hintMode: hintMode)
        }

        Window("Welcome to JUMP", id: OnboardingView.windowID) {
            OnboardingView(permission: permission)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(permission.isTrusted ? .suppressed : .presented)
    }
}
