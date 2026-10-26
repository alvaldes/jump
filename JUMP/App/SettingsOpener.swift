import SwiftUI

/// Opens Settings from outside SwiftUI views (⌘, inside a mode).
///
/// SwiftUI only hands out `openSettings` to views, so the always-present menu
/// bar label lends it here.
@MainActor
final class SettingsOpener {
    fileprivate var action: OpenSettingsAction?

    func open() {
        // A menu bar agent is not active; bring the window to the front.
        NSApp.activate()
        action?()
    }
}

/// The menu bar icon, which also hands its `openSettings` to `SettingsOpener`.
struct MenuBarLabel: View {
    let imageName: String
    let opener: SettingsOpener

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(imageName)
            .accessibilityLabel("JUMP")
            .onAppear { opener.action = openSettings }
    }
}
