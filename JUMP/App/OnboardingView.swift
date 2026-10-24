import JumpKit
import SwiftUI

/// First-run window asking for Accessibility access. Closes itself once granted.
struct OnboardingView: View {
    static let windowID = "onboarding"

    let permission: AccessibilityPermission

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 8) {
                Text("Navigate your Mac without a mouse")
                    .font(.title2.weight(.semibold))
                Text("JUMP needs Accessibility access to find buttons and links on screen and click them for you.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Open System Settings", systemImage: "1.circle")
                Label("Turn on JUMP under Accessibility", systemImage: "2.circle")
                Label("This window closes automatically", systemImage: "3.circle")
            }
            .font(.callout)

            Button("Open System Settings") {
                if !permission.isTrusted {
                    permission.request()
                }
                permission.openSystemSettings()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 420)
        .onAppear { permission.refresh() }
        .onChange(of: permission.isTrusted) { _, isTrusted in
            if isTrusted {
                dismissWindow(id: Self.windowID)
            }
        }
    }
}
