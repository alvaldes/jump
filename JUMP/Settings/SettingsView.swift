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
                Picker("Hint theme:", selection: Binding(
                    get: { settings.hintAppearance.theme },
                    set: { settings.setHintTheme($0) }
                )) {
                    ForEach(HintTheme.allCases, id: \.self) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                LabeledContent("Hint size:") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(settings.hintAppearance.size) },
                                set: { settings.setHintSize(CGFloat($0)) }
                            ),
                            in: Double(HintAppearance.sizeRange.lowerBound)...Double(HintAppearance.sizeRange.upperBound),
                            step: 1
                        )
                        Text("\(Int(settings.hintAppearance.size)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Liquid Glass", isOn: Binding(
                    get: { settings.hintAppearance.glass },
                    set: { settings.setHintGlass($0) }
                ))
                Text("Applies to the next hints shown. Liquid Glass tints the glass with the theme's color.")
                    .foregroundStyle(.secondary)
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
