import JumpKit
import SwiftUI

/// The areas of the Settings window, in sidebar order.
enum SettingsArea: String, CaseIterable, Identifiable {
    case about, general, shortcuts, appearance, behavior, permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .appearance: "Appearance"
        case .behavior: "Behavior"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .appearance: "paintpalette"
        case .behavior: "cursorarrow.click.2"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

/// The Settings window: a branded sidebar and one pane of cards per area.
struct SettingsView: View {
    let settings: JumpSettings
    let launchAtLogin: LaunchAtLogin
    let accessibility: AccessibilityPermission
    let screenRecording: ScreenRecordingPermission
    let recognizer: ScreenTextRecognizer

    /// Every opening starts on About.
    @State var area: SettingsArea = .about
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $area)
            Divider()
            ScrollView {
                pane
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(width: 780, height: 560)
        .background(Brand.backdrop(scheme))
        .background(WindowTitle("JUMP"))
        .onDisappear { area = .about }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings.
            accessibility.refresh()
            screenRecording.refresh()
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch area {
        case .general: GeneralSettings(settings: settings, launchAtLogin: launchAtLogin)
        case .shortcuts: ShortcutsSettings()
        case .appearance: AppearanceSettings(settings: settings)
        case .behavior: BehaviorSettings(settings: settings, screenRecording: screenRecording, recognizer: recognizer)
        case .permissions: PermissionsSettings(accessibility: accessibility, screenRecording: screenRecording)
        case .about: AboutSettings()
        }
    }
}

/// The app icon and version on top, the areas below; the selected one sits
/// on a keycap face with a homing bump.
struct SettingsSidebar: View {
    @Binding var selection: SettingsArea

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text("JUMP").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Version \(AppVersion.short)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 18)

            ForEach(SettingsArea.allCases) { area in
                Button {
                    selection = area
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: area.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(area.title)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(.rect)
                    .background {
                        if selection == area {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Brand.cardWash(scheme))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Brand.hairline(scheme)))
                                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 2, y: 1)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if selection == area { HomingBump().rotationEffect(.degrees(90)).padding(.trailing, 2) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == area ? .isSelected : [])
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 200)
        .background(.ultraThinMaterial)
    }
}

/// Names the hosting window: the `Settings` scene calls it "<app> Settings".
private struct WindowTitle: NSViewRepresentable {
    let title: String

    init(_ title: String) { self.title = title }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // The view joins its window after this pass.
        DispatchQueue.main.async { view.window?.title = title }
    }
}

enum AppVersion {
    static let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
}
