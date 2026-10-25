import JumpKit
import SwiftUI

struct GeneralSettings: View {
    let settings: JumpSettings
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        SettingsPane {
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
        }
        .onAppear { launchAtLogin.refresh() }
    }
}
