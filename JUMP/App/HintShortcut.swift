import Foundation
import KeyboardShortcuts
import Observation

/// The hint shortcut, observable so the menu shows a change right away:
/// KeyboardShortcuts stores shortcuts outside SwiftUI's view of the app.
@MainActor
@Observable
final class HintShortcut {
    private(set) var shortcut = KeyboardShortcuts.getShortcut(for: .activateHints)
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init() {
        // KeyboardShortcuts posts this for every change but keeps the name internal.
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.shortcut = KeyboardShortcuts.getShortcut(for: .activateHints)
            }
        }
    }
}
