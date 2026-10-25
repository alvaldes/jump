import AppKit
import SwiftUI

struct AboutSettings: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                Text("JUMP").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Keyboard-driven screen navigation for macOS.").foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Keycap(label: "v\(AppVersion.short)", minWidth: 60)
                    Keycap(label: "build \(AppVersion.build)", minWidth: 60)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RadialGradient(colors: [Brand.graphite.opacity(scheme == .dark ? 0.6 : 0.18), .clear],
                               center: .top, startRadius: 10, endRadius: 320)
            )

            SettingsCard(title: "Credits", symbol: "heart") {
                LinkRow(title: "License", label: "GPL-3.0", url: "https://www.gnu.org/licenses/gpl-3.0.html")
                Divider()
                LinkRow(title: "Based on", label: "Vimac by Dexter Leng and contributors", url: "https://github.com/nchudleigh/vimac")
                Divider()
                LinkRow(title: "Source code", label: "github.com/alvaldes/jump", url: "https://github.com/alvaldes/jump")
                Divider()
                LinkRow(title: "Feedback", label: "Report an issue", url: "https://github.com/alvaldes/jump/issues")
            }
        }
    }
}

private struct LinkRow: View {
    let title: String
    let label: String
    let url: String

    var body: some View {
        SettingRow(title: title) {
            if let destination = URL(string: url) {
                Link(label, destination: destination)
            }
        }
    }
}
