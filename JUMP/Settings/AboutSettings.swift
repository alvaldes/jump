import AppKit
import SwiftUI

struct AboutSettings: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

    var body: some View {
        SettingsPane {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("JUMP")
                        .font(.title.bold())
                    Text("Version \(version) (\(build))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Keyboard-driven screen navigation for macOS.")
                }
                .frame(maxWidth: .infinity)
            }

            Section {
                LabeledContent("License") {
                    Link("GPL-3.0", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                }
                LabeledContent("Based on") {
                    Link("Vimac by Dexter Leng and contributors", destination: URL(string: "https://github.com/nchudleigh/vimac")!)
                }
                LabeledContent("Source code") {
                    Link("github.com/alvaldes/jump", destination: URL(string: "https://github.com/alvaldes/jump")!)
                }
                LabeledContent("Feedback") {
                    Link("Report an issue", destination: URL(string: "https://github.com/alvaldes/jump/issues")!)
                }
            }
        }
    }
}
