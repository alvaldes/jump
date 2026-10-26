import AppKit
import SwiftUI

/// Sized to fit the window without scrolling: it is the first pane people see.
struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                // The icon's own shadow is the glow; a backdrop behind the block
                // showed as a box of a different color.
                Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 104, height: 104)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 7)
                Text("JUMP").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Keyboard-driven screen navigation for macOS.").foregroundStyle(.secondary)
                Keycap(label: "v\(AppVersion.short)", minWidth: 60)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)

            SettingsCard(title: "Credits", symbol: "heart") {
                LinkRow(title: "Created by", label: "@alvaldes", url: "https://alvaldes.vercel.app")
                Divider()
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
