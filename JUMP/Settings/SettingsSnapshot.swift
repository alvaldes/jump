#if DEBUG
import AppKit
import JumpKit
import SwiftUI

/// Debug only: renders every Settings area, light and dark, to PNG files in an
/// offscreen window that is never shown, so the design can be reviewed
/// without opening the app. Run with `JUMP_RENDER_SETTINGS=<directory>`.
enum SettingsSnapshot {
    static func renderIfRequested() {
        guard let directory = ProcessInfo.processInfo.environment["JUMP_RENDER_SETTINGS"] else { return }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let settings = JumpSettings()
        let updates = snapshotUpdates()
        for area in SettingsArea.allCases {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let view = SettingsView(settings: settings, launchAtLogin: LaunchAtLogin(),
                                        accessibility: AccessibilityPermission(),
                                        screenRecording: ScreenRecordingPermission(),
                                        recognizer: ScreenTextRecognizer(), updates: updates, area: area)
                render(view, appearance: appearance, to: output.appending(path: "\(area.rawValue)-\(name).png"))
            }
        }
        // The General pane is taller than the window; this shows all of it.
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let pane = GeneralSettings(settings: settings, launchAtLogin: LaunchAtLogin(), updates: updates)
                .padding(28)
                .frame(width: 580)
                .background(Brand.backdrop(appearance == .darkAqua ? .dark : .light))
                .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
            render(pane, appearance: appearance, size: CGSize(width: 580, height: 1_000),
                   to: output.appending(path: "general-full-\(name).png"))
        }
        exit(0)
    }

    /// Never asks GitHub. With `JUMP_FAKE_UPDATE=<version>` it shows that version as available.
    private static func snapshotUpdates() -> UpdateChecker {
        guard let version = ProcessInfo.processInfo.environment["JUMP_FAKE_UPDATE"] else {
            return UpdateChecker(currentVersion: AppVersion.short, schedule: { .off })
        }
        let release = AppRelease(
            version: version,
            pageURL: URL(string: "https://github.com/alvaldes/jump/releases")!,
            highlights: ["Update notices in the menu and in Settings",
                         "Choose how often JUMP checks for updates",
                         "A badge next to the version when a new one is out"]
        )
        let updates = UpdateChecker(currentVersion: AppVersion.short, schedule: { .off },
                                    client: UpdateClient(fetchLatest: { release }, now: { Date() }))
        Task { await updates.checkNow() }
        while updates.available == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return updates
    }

    private static func render(_ view: some View, appearance: NSAppearance.Name,
                               size: CGSize = CGSize(width: 780, height: 588), to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI settle its first layout pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
