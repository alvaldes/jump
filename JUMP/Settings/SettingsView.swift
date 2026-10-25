import JumpKit
import SwiftUI

/// The Settings window: one toolbar tab per area.
struct SettingsView: View {
    let settings: JumpSettings
    let launchAtLogin: LaunchAtLogin
    let accessibility: AccessibilityPermission
    let screenRecording: ScreenRecordingPermission
    let recognizer: ScreenTextRecognizer

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(settings: settings, launchAtLogin: launchAtLogin)
            }
            Tab("Shortcuts", systemImage: "command") {
                ShortcutsSettings()
            }
            Tab("Appearance", systemImage: "paintpalette") {
                AppearanceSettings(settings: settings)
            }
            Tab("Behavior", systemImage: "cursorarrow.click.2") {
                BehaviorSettings(settings: settings, screenRecording: screenRecording, recognizer: recognizer)
            }
            Tab("Permissions", systemImage: "lock.shield") {
                PermissionsSettings(accessibility: accessibility, screenRecording: screenRecording)
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettings()
            }
        }
        .frame(width: 480)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings.
            accessibility.refresh()
            screenRecording.refresh()
        }
    }
}

/// Shared layout of every tab: a grouped form sized to its content.
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
    }
}
