import JumpKit
import KeyboardShortcuts
import SwiftUI

@main
struct JumpApp: App {
    @State private var permission: AccessibilityPermission
    @State private var hintMode: HintModeController
    @State private var scrollMode: ScrollModeController
    @State private var settings: JumpSettings
    @State private var launchAtLogin = LaunchAtLogin()

    init() {
        let permission = AccessibilityPermission()
        let settings = JumpSettings()
        // One overlay for both modes: they never show at the same time.
        let overlay = HintOverlay()
        let hintMode = HintModeController(permission: permission, settings: settings, overlay: overlay)
        let scrollMode = ScrollModeController(permission: permission, overlay: overlay)
        _scrollMode = State(initialValue: scrollMode)
        _permission = State(initialValue: permission)
        _settings = State(initialValue: settings)
        _hintMode = State(initialValue: hintMode)
        // Track grants and revocations for the whole app lifetime.
        Task { await permission.monitor() }
        KeyboardShortcuts.onKeyDown(for: .activateHints) {
            scrollMode.deactivate()
            hintMode.toggle()
        }
        KeyboardShortcuts.onKeyDown(for: .activateScroll) {
            hintMode.dismiss()
            scrollMode.toggle()
        }
    }

    var body: some Scene {
        MenuBarExtra("JUMP", systemImage: "j.square") {
            MenuContent(permission: permission, hintMode: hintMode)
        }

        Window("Welcome to JUMP", id: OnboardingView.windowID) {
            OnboardingView(permission: permission)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(permission.isTrusted ? .suppressed : .presented)

        Settings {
            SettingsView(settings: settings, launchAtLogin: launchAtLogin)
        }
    }
}
