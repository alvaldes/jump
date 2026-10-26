import JumpKit
import KeyboardShortcuts
import SwiftUI

typealias LiveHintMode = HintMode<AXNode>
typealias LiveScrollMode = ScrollMode<Scroller<AXScrollControl>>
typealias LiveTextSearchMode = TextSearchMode<AXNode>

@main
struct JumpApp: App {
    @State private var permission: AccessibilityPermission
    @State private var settings: JumpSettings
    @State private var hintMode: LiveHintMode
    @State private var searchMode: LiveTextSearchMode
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var screenRecording = ScreenRecordingPermission()
    @State private var hintShortcut = HintShortcut()
    private let recognizer: ScreenTextRecognizer
    private let services: AppServices
    private let switcher: ModeSwitcher<AXNode, Scroller<AXScrollControl>>
    private let settingsOpener: SettingsOpener

    init() {
        #if DEBUG
        SettingsSnapshot.renderIfRequested()
        #endif
        let permission = AccessibilityPermission()
        let settings = JumpSettings()
        // One overlay for every mode: they never show at the same time.
        let overlay = HintOverlay(hintAppearance: { settings.hintAppearance },
                                  showsScrollOutline: { settings.showsScrollOutline })
        let services = AppServices(permission: permission, settings: settings, overlay: overlay)
        let webAccessibility = services.webAccessibility
        let settingsOpener = SettingsOpener()

        let hintMode = LiveHintMode(
            overlay: overlay,
            input: AppKitModeInput(overlay: overlay, openSettings: { settingsOpener.open() }),
            isTrusted: { permission.isTrusted },
            hintCharacters: { settings.hintCharacters },
            actionModifiers: { settings.actionModifiers },
            frontmostApp: FrontmostApp.current,
            // Usually already done on activation; covers apps that were in front before JUMP started.
            prepareApp: { app in await webAccessibility.enable(pid: app.pid, bundleIdentifier: app.bundleIdentifier) },
            scan: { app in try await FocusedWindowScanner.scan(pid: app.pid) },
            perform: { action, element in await ElementActions.perform(action, on: element) }
        )
        let scrollMode = LiveScrollMode(
            overlay: overlay,
            pointer: SystemPointer(),
            input: AppKitModeInput(overlay: overlay, openSettings: { settingsOpener.open() }),
            driver: Scroller<AXScrollControl>(speed: { settings.scrollSpeed }),
            isTrusted: { permission.isTrusted },
            frontmostApp: FrontmostApp.current,
            screens: ScreenGeometry.screenFramesInAXCoordinates,
            findTargets: { app, screens in try await FocusedWindowScanner.scrollTargets(pid: app.pid, screens: screens) }
        )
        let recognizer = ScreenTextRecognizer()
        let searchMode = LiveTextSearchMode(
            overlay: overlay,
            input: AppKitModeInput(overlay: overlay, openSettings: { settingsOpener.open() }),
            isTrusted: { permission.isTrusted },
            frontmostApp: FrontmostApp.current,
            prepareApp: { app in await webAccessibility.enable(pid: app.pid, bundleIdentifier: app.bundleIdentifier) },
            windowFrame: { app in try await TextCollector.windowFrame(pid: app.pid) },
            collect: { app in try await TextCollector.collect(pid: app.pid) },
            locate: { match in await TextCollector.wordBounds(for: match) },
            perform: { action, match in await TextCollector.jump(action, to: match) },
            screenText: ScreenTextSource(
                // Checked at each search: access can be granted or revoked at any time.
                isEnabled: { settings.recognizesScreenText && ScreenTextRecognizer.hasScreenRecordingAccess },
                recognize: { app, frame in try await recognizer.recognize(pid: app.pid, windowFrame: frame) },
                perform: { action, match in await ScreenTextRecognizer.jump(action, to: match) }
            ),
            actionModifiers: { settings.actionModifiers }
        )
        let switcher = ModeSwitcher(hints: hintMode, scroll: scrollMode, search: searchMode)

        _permission = State(initialValue: permission)
        _settings = State(initialValue: settings)
        _hintMode = State(initialValue: hintMode)
        _searchMode = State(initialValue: searchMode)
        self.services = services
        self.recognizer = recognizer
        self.switcher = switcher
        self.settingsOpener = settingsOpener

        // NSApp exists once the app finishes starting.
        DispatchQueue.main.async { DockPresence.apply(settings) }

        // The window list takes ~100 ms to load; the first search should not wait for it.
        if settings.recognizesScreenText, ScreenTextRecognizer.hasScreenRecordingAccess {
            Task { await recognizer.prefetch() }
        }

        // Track grants and revocations for the whole app lifetime.
        Task { await permission.monitor() }
        KeyboardShortcuts.onKeyDown(for: .activateHints) { switcher.activateHints() }
        KeyboardShortcuts.onKeyDown(for: .activateScroll) { switcher.activateScroll() }
        KeyboardShortcuts.onKeyDown(for: .activateSearch) { switcher.activateSearch() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(permission: permission, hintMode: hintMode, searchMode: searchMode, settingsOpener: settingsOpener,
                        hintShortcut: hintShortcut)
        } label: {
            MenuBarLabel(imageName: settings.menuBarIcon.imageName, opener: settingsOpener)
        }

        Window("Welcome to JUMP", id: OnboardingView.windowID) {
            OnboardingView(permission: permission)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(permission.isTrusted ? .suppressed : .presented)

        Settings {
            SettingsView(settings: settings, launchAtLogin: launchAtLogin, accessibility: permission,
                         screenRecording: screenRecording, recognizer: recognizer)
        }
    }
}
