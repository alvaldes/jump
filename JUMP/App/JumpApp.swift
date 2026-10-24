import JumpKit
import KeyboardShortcuts
import SwiftUI

@main
struct JumpApp: App {
    @State private var permission: AccessibilityPermission
    @State private var scanController: ScanController

    init() {
        let permission = AccessibilityPermission()
        let scanController = ScanController(permission: permission)
        _permission = State(initialValue: permission)
        _scanController = State(initialValue: scanController)
        // Track grants and revocations for the whole app lifetime.
        Task { await permission.monitor() }
        KeyboardShortcuts.onKeyDown(for: .activateHints) {
            scanController.scanFocusedWindow()
        }
    }

    var body: some Scene {
        MenuBarExtra("JUMP", systemImage: "keyboard") {
            MenuContent(permission: permission, scanController: scanController)
        }

        Window("Welcome to JUMP", id: OnboardingView.windowID) {
            OnboardingView(permission: permission)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(permission.isTrusted ? .suppressed : .presented)
    }
}
