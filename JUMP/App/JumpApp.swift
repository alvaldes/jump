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
    private let services: AppServices
    private let switcher: ModeSwitcher<AXNode, Scroller<AXScrollControl>>

    init() {
        let permission = AccessibilityPermission()
        let settings = JumpSettings()
        // One overlay for every mode: they never show at the same time.
        let overlay = HintOverlay(hintAppearance: { settings.hintAppearance })
        let services = AppServices(permission: permission, overlay: overlay)
        let webAccessibility = services.webAccessibility

        let hintMode = LiveHintMode(
            overlay: overlay,
            input: AppKitModeInput(overlay: overlay),
            isTrusted: { permission.isTrusted },
            hintCharacters: { settings.hintCharacters },
            frontmostApp: FrontmostApp.current,
            // Usually already done on activation; covers apps that were in front before JUMP started.
            prepareApp: { app in await webAccessibility.enable(pid: app.pid, bundleIdentifier: app.bundleIdentifier) },
            scan: { app in try await FocusedWindowScanner.scan(pid: app.pid) },
            perform: { action, element in await ElementActions.perform(action, on: element) }
        )
        let scrollMode = LiveScrollMode(
            overlay: overlay,
            pointer: SystemPointer(),
            input: AppKitModeInput(overlay: overlay),
            driver: Scroller<AXScrollControl>(),
            isTrusted: { permission.isTrusted },
            frontmostApp: FrontmostApp.current,
            screens: ScreenGeometry.screenFramesInAXCoordinates,
            findTargets: { app, screens in try await FocusedWindowScanner.scrollTargets(pid: app.pid, screens: screens) }
        )
        let searchMode = LiveTextSearchMode(
            overlay: overlay,
            input: AppKitModeInput(overlay: overlay),
            isTrusted: { permission.isTrusted },
            frontmostApp: FrontmostApp.current,
            prepareApp: { app in await webAccessibility.enable(pid: app.pid, bundleIdentifier: app.bundleIdentifier) },
            windowFrame: { app in try await TextCollector.windowFrame(pid: app.pid) },
            collect: { app in try await TextCollector.collect(pid: app.pid) },
            locate: { match in await TextCollector.wordBounds(for: match) },
            perform: { action, match in await TextCollector.jump(action, to: match) }
        )
        let switcher = ModeSwitcher(hints: hintMode, scroll: scrollMode, search: searchMode)

        _permission = State(initialValue: permission)
        _settings = State(initialValue: settings)
        _hintMode = State(initialValue: hintMode)
        _searchMode = State(initialValue: searchMode)
        self.services = services
        self.switcher = switcher

        // NSApp exists once the app finishes starting.
        DispatchQueue.main.async { DockPresence.apply(settings) }

        // Track grants and revocations for the whole app lifetime.
        Task { await permission.monitor() }
        KeyboardShortcuts.onKeyDown(for: .activateHints) { switcher.activateHints() }
        KeyboardShortcuts.onKeyDown(for: .activateScroll) { switcher.activateScroll() }
        KeyboardShortcuts.onKeyDown(for: .activateSearch) { switcher.activateSearch() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(permission: permission, hintMode: hintMode, searchMode: searchMode)
        } label: {
            Image(settings.menuBarIcon.imageName)
                .accessibilityLabel("JUMP")
        }

        Window("Welcome to JUMP", id: OnboardingView.windowID) {
            OnboardingView(permission: permission)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(permission.isTrusted ? .suppressed : .presented)

        Settings {
            SettingsView(settings: settings, launchAtLogin: launchAtLogin)
        }
    }
}
