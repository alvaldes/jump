import JumpKit
import SwiftUI

struct GeneralSettings: View {
    let settings: JumpSettings
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(title: "General", subtitle: "How JUMP starts and where it lives.")

            SettingsCard(title: "Startup", symbol: "power") {
                SettingRow(title: "Launch at login") {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                if launchAtLogin.needsApproval {
                    SettingRow(title: "Approval needed", detail: "Allow JUMP in Login Items to finish turning this on.") {
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            SettingsCard(title: "Menu bar", symbol: "menubar.rectangle") {
                HStack(spacing: 10) {
                    ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                        IconTile(image: Image(icon.imageName), title: icon.title, isSelected: settings.menuBarIcon == icon) {
                            settings.setMenuBarIcon(icon)
                        }
                    }
                }
            }

            SettingsCard(title: "Dock", symbol: "dock.rectangle",
                         subtitle: "Applies while JUMP runs; Finder and Spotlight always show the official icon.") {
                SettingRow(title: "Show in Dock") {
                    Toggle("", isOn: Binding(
                        get: { settings.showInDock },
                        set: {
                            settings.setShowInDock($0)
                            DockPresence.apply(settings)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                HStack(spacing: 10) {
                    ForEach(AppIconChoice.allCases, id: \.self) { icon in
                        IconTile(image: Image(nsImage: DockPresence.preview(icon)), title: icon.title,
                                 isSelected: settings.appIcon == icon, iconSize: 48, isTemplate: false) {
                            settings.setAppIcon(icon)
                            DockPresence.apply(settings)
                        }
                    }
                }
                .disabled(!settings.showInDock)
                .opacity(settings.showInDock ? 1 : 0.5)
            }
        }
        .onAppear { launchAtLogin.refresh() }
    }
}

/// A choosable icon on a keycap-like tile.
struct IconTile: View {
    let image: Image
    let title: String
    let isSelected: Bool
    var iconSize: CGFloat = 22
    /// Menu bar icons are templates; app icons keep their colors.
    var isTemplate = true
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                image.renderingMode(isTemplate ? .template : .original).resizable()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(.primary)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Brand.cardWash(scheme), in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.primary.opacity(0.7) : Brand.hairline(scheme),
                                  lineWidth: isSelected ? 1.5 : 1)
            )
            .overlay(alignment: .bottom) {
                if isSelected { HomingBump().padding(.bottom, 4) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
