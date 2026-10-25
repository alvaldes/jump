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
        for area in SettingsArea.allCases {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let view = SettingsView(settings: settings, launchAtLogin: LaunchAtLogin(),
                                        accessibility: AccessibilityPermission(),
                                        screenRecording: ScreenRecordingPermission(),
                                        recognizer: ScreenTextRecognizer(), area: area)
                render(view, appearance: appearance, to: output.appending(path: "\(area.rawValue)-\(name).png"))
            }
        }
        exit(0)
    }

    private static func render(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: 780, height: 560)
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
