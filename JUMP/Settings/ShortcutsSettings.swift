import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettings: View {
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
