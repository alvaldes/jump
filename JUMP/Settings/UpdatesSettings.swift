import AppKit
import JumpKit
import SwiftUI

/// JUMP is not notarized, so it only tells about a new version and links to it.
struct UpdatesCard: View {
    let settings: JumpSettings
    let updates: UpdateChecker

    var body: some View {
        SettingsCard(title: "Updates", symbol: "arrow.down.circle") {
            SettingRow(title: "Check automatically",
                       detail: "Asks GitHub for the latest release; a new version shows here and in the menu bar menu.") {
                Picker("", selection: Binding(
                    get: { settings.updateCheckSchedule },
                    set: { schedule in
                        settings.setUpdateCheckSchedule(schedule)
                        Task { await updates.checkIfDue() }
                    }
                )) {
                    ForEach(UpdateCheckSchedule.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            if let release = updates.available {
                SettingRow(title: "JUMP \(release.version) is available",
                           detail: "Installed with Homebrew? Run brew upgrade --cask jump. Otherwise download it and replace JUMP in Applications.") {
                    Button("Download") { NSWorkspace.shared.open(release.pageURL) }
                }
                if !release.highlights.isEmpty {
                    ReleaseHighlights(highlights: release.highlights)
                }
            } else {
                SettingRow(title: status, detail: lastCheck) {
                    Button("Check Now") { Task { await updates.checkNow() } }
                        .disabled(updates.isChecking)
                }
            }
        }
    }

    private var status: String {
        if updates.isChecking { return "Checking…" }
        if updates.lastCheckFailed { return "Couldn't reach GitHub" }
        return updates.lastCheck == nil ? "Not checked yet" : "JUMP is up to date"
    }

    private var lastCheck: String? {
        updates.lastCheck.map { "Last checked \($0.formatted(.relative(presentation: .named)))." }
    }
}

/// What the new version brings, from its release notes.
private struct ReleaseHighlights: View {
    let highlights: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's new").font(.subheadline.weight(.semibold))
            ForEach(Array(highlights.enumerated()), id: \.offset) { _, highlight in
                Label {
                    Text(highlight).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "sparkle").foregroundStyle(.tint)
                }
                .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Next to the version number: says a newer one is out and opens its release page.
struct UpdateBadge: View {
    let updates: UpdateChecker

    var body: some View {
        if let release = updates.available {
            Button { NSWorkspace.shared.open(release.pageURL) } label: {
                Label("\(release.version) available", systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.tint.opacity(0.15)))
                    .foregroundStyle(.tint)
                    // One line, even in the narrow sidebar.
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Open the release page of JUMP \(release.version)")
        }
    }
}

private extension UpdateCheckSchedule {
    var title: String {
        switch self {
        case .off: "Off"
        case .every6Hours: "Every 6 hours"
        case .daily: "Every day"
        case .weekly: "Every week"
        }
    }
}
