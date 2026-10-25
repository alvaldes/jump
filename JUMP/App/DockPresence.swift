import AppKit
import JumpKit

/// JUMP is a menu bar app (`LSUIElement`); on request it also shows in the
/// Dock, with the chosen Dock tile icon.
enum DockPresence {
    static func apply(showInDock: Bool, icon: AppIconChoice) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        // `nil` restores the bundle's own icon.
        NSApp.applicationIconImage = icon.imageName.flatMap { NSImage(named: $0) }
    }

    static func apply(_ settings: JumpSettings) {
        apply(showInDock: settings.showInDock, icon: settings.appIcon)
    }
}
