import JumpKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    let settings: JumpSettings
    let launchAtLogin: LaunchAtLogin

    @State private var characters = ""
    @State private var charactersRejected = false

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Show hints:", name: .activateHints)
                KeyboardShortcuts.Recorder("Scroll mode:", name: .activateScroll)
            }

            Section {
                LabeledContent("Hint characters:") {
                    TextField("Hint characters", text: $characters)
                        .labelsHidden()
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                        .onSubmit(applyCharacters)
                }
                if charactersRejected {
                    Text("Use at least two different letters.")
                        .foregroundStyle(.red)
                } else {
                    Text("Labels are built from these letters, first ones first. Press Return to apply.")
                        .foregroundStyle(.secondary)
                }
                Button("Restore Default") {
                    characters = HintLabels.defaultCharacters
                    applyCharacters()
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.needsApproval {
                    Text("Allow JUMP in Login Items to finish turning this on.")
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            characters = settings.hintCharacters
            launchAtLogin.refresh()
        }
    }

    private func applyCharacters() {
        charactersRejected = !settings.setHintCharacters(characters)
        characters = settings.hintCharacters
    }
}
