import JumpKit
import SwiftUI

struct PermissionsSettings: View {
    let accessibility: AccessibilityPermission
    let screenRecording: ScreenRecordingPermission

    var body: some View {
        SettingsPane {
            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Required. Lets JUMP read and click other apps' elements.",
                    isGranted: accessibility.isTrusted,
                    open: accessibility.openSystemSettings
                )
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Optional. Only for recognizing text on screen (OCR) in text search; never requested unless you turn that on.",
                    isGranted: screenRecording.isGranted,
                    open: screenRecording.openPrivacySettings
                )
            }
        }
        .onAppear {
            accessibility.refresh()
            screenRecording.refresh()
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let open: () -> Void

    var body: some View {
        LabeledContent {
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open Privacy Settings", action: open)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}
