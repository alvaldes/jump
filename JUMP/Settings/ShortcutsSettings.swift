import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettings: View {
    var body: some View {
        SettingsPane {
            Section {
                KeyboardShortcuts.Recorder("Show hints:", name: .activateHints)
                KeyboardShortcuts.Recorder("Scroll mode:", name: .activateScroll)
                KeyboardShortcuts.Recorder("Search text:", name: .activateSearch)
            } footer: {
                Text("Press a shortcut again while its mode is open to close it.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
