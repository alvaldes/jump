import AppKit
import JumpKit
import os

/// JUMP is a menu bar app (`LSUIElement`); on request it also shows in the
/// Dock, with the chosen Dock tile icon.
enum DockPresence {
    private static let logger = Logger(subsystem: "com.alvaldes.jump", category: "dock")

    static func apply(showInDock: Bool, icon: AppIconChoice) {
        // Leaving the Dock deactivates the app, which would drop the Settings
        // window behind other apps while the user is still in it.
        let keyWindow = NSApp.keyWindow
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if let keyWindow {
            NSApp.activate()
            keyWindow.makeKeyAndOrderFront(nil)
        }

        // `nil` restores the bundle's own icon.
        var image: NSImage?
        if let name = icon.imageName {
            image = NSImage(named: name)
            if image == nil {
                logger.error("Dock icon \(name, privacy: .public) is missing; showing the official icon")
            }
        }
        NSApp.applicationIconImage = image
    }

    static func apply(_ settings: JumpSettings) {
        apply(showInDock: settings.showInDock, icon: settings.appIcon)
    }
}
