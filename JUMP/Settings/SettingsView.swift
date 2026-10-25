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
                KeyboardShortcuts.Recorder("Search text:", name: .activateSearch)
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
                Picker("Liquid Glass:", selection: Binding(
                    get: { settings.hintAppearance.glass },
                    set: { settings.setHintGlass($0) }
                )) {
                    ForEach(HintGlass.allCases, id: \.self) { glass in
                        Text(glass.title).tag(glass)
                    }
                }
                Text("Applies to the next hints shown. Regular glass is frosted, Clear is transparent; Accent and Classic tint it.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Menu bar icon:", selection: Binding(
                    get: { settings.menuBarIcon },
                    set: { settings.setMenuBarIcon($0) }
                )) {
                    ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                        Label {
                            Text(icon.title)
                        } icon: {
                            Image(icon.imageName)
                        }
                        .tag(icon)
                    }
                }
                Toggle("Show in Dock", isOn: Binding(
                    get: { settings.showInDock },
                    set: {
                        settings.setShowInDock($0)
                        DockPresence.apply(settings)
                    }
                ))
                Picker("Dock icon:", selection: Binding(
                    get: { settings.appIcon },
                    set: {
                        settings.setAppIcon($0)
                        DockPresence.apply(settings)
                    }
                )) {
                    ForEach(AppIconChoice.allCases, id: \.self) { icon in
                        Text(icon.title).tag(icon)
                    }
                }
                .disabled(!settings.showInDock)
                Text("The Dock icon applies while JUMP runs; Finder and Spotlight always show the official icon.")
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
