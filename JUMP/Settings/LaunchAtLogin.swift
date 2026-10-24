import OSLog
import ServiceManagement

/// Starts JUMP when the user logs in, through the system login items.
@Observable
final class LaunchAtLogin {
    private(set) var status = SMAppService.mainApp.status
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.alvaldes.jump", category: "settings")

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    /// The user must allow JUMP in System Settings > General > Login Items.
    var needsApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            logger.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
