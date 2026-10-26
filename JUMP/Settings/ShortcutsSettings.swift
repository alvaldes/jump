import JumpKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutsSettings: View {
    let settings: JumpSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(title: "Shortcuts", subtitle: "Press a shortcut again while its mode is open to close it.")
            SettingsCard(title: "Modes", symbol: "keyboard") {
                ShortcutRow(name: .activateHints, title: "Show hints", detail: "Label every clickable element.")
                Divider()
                ShortcutRow(name: .activateScroll, title: "Scroll mode", detail: "h j k l, d u, gg G, Tab.")
                Divider()
                ShortcutRow(name: .activateSearch, title: "Search text", detail: "Find visible text and jump to it.")
            }

            SettingsCard(title: "Excluded apps", symbol: "nosign",
                         subtitle: "JUMP's shortcuts stay off while one of these apps is in front, so the app gets those keys.") {
                ForEach(settings.excludedApps, id: \.self) { bundleIdentifier in
                    ExcludedAppRow(app: ExcludedApp(bundleIdentifier: bundleIdentifier)) {
                        settings.includeApp(bundleIdentifier)
                    }
                }
                Button("Add App…", action: chooseApps)
            }
        }
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
                  // Excluding JUMP would turn the shortcuts off while Settings is open.
                  bundleIdentifier != Bundle.main.bundleIdentifier
            else { continue }
            settings.excludeApp(bundleIdentifier)
        }
    }
}

/// An excluded app's name and icon, looked up from its bundle identifier.
private struct ExcludedApp {
    let name: String
    let icon: NSImage

    init(bundleIdentifier: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
                .replacing(/\.app$/, with: "")
            icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        } else {
            // Uninstalled apps stay listed by identifier so they can still be removed.
            name = bundleIdentifier
            icon = NSWorkspace.shared.icon(for: .application)
        }
    }
}

private struct ExcludedAppRow: View {
    let app: ExcludedApp
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon).resizable().frame(width: 24, height: 24)
            Text(app.name)
            Spacer(minLength: 8)
            Button("Remove", systemImage: "minus.circle", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Turn JUMP back on in \(app.name)")
        }
    }
}

/// A mode's shortcut as keycaps, with the recorder to change it.
private struct ShortcutRow: View {
    let name: KeyboardShortcuts.Name
    let title: String
    let detail: String

    @State private var shortcut: KeyboardShortcuts.Shortcut?

    var body: some View {
        SettingRow(title: title, detail: detail) {
            HStack(spacing: 12) {
                ShortcutKeycaps(shortcut: shortcut)
                KeyboardShortcuts.Recorder(for: name) { shortcut = $0 }
                    .frame(width: 130)
            }
        }
        .onAppear { shortcut = KeyboardShortcuts.getShortcut(for: name) }
    }
}
