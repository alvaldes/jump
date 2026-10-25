import JumpKit
import SwiftUI

struct PermissionsSettings: View {
    let accessibility: AccessibilityPermission
    let screenRecording: ScreenRecordingPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(title: "Permissions", subtitle: "What JUMP is allowed to do on this Mac.")
            PermissionCard(title: "Accessibility", symbol: "accessibility", requirement: "Required",
                           detail: "Lets JUMP read and click other apps' elements.",
                           isGranted: accessibility.isTrusted, open: accessibility.openSystemSettings)
            PermissionCard(title: "Screen Recording", symbol: "rectangle.dashed.badge.record", requirement: "Optional",
                           detail: "Only for recognizing text on screen (OCR). Never requested unless you turn that on. Captures stay in memory.",
                           isGranted: screenRecording.isGranted, open: screenRecording.openPrivacySettings)
        }
        .onAppear {
            accessibility.refresh()
            screenRecording.refresh()
        }
    }
}

private struct PermissionCard: View {
    let title: String
    let symbol: String
    let requirement: String
    let detail: String
    let isGranted: Bool
    let open: () -> Void

    var body: some View {
        SettingsCard(title: title, symbol: symbol, subtitle: requirement) {
            SettingRow(title: isGranted ? "Allowed" : "Not allowed", detail: detail) {
                if isGranted {
                    StatusDot(isOn: true)
                } else {
                    HStack(spacing: 10) {
                        StatusDot(isOn: false)
                        Button("Open Privacy Settings", action: open)
                    }
                }
            }
        }
    }
}
