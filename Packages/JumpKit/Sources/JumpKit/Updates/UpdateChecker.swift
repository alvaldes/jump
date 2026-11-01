import Foundation
import Observation

/// A published version of JUMP.
nonisolated public struct AppRelease: Sendable, Equatable {
    /// Without the tag's leading "v", e.g. "1.2.0".
    public var version: String
    /// The release page: notes and the DMG.
    public var pageURL: URL
    /// What the version brings: the top-level bullets of its release notes.
    public var highlights: [String]

    public init(version: String, pageURL: URL, highlights: [String] = []) {
        self.version = version
        self.pageURL = pageURL
        self.highlights = highlights
    }
}

/// How often JUMP looks for a new version on its own.
nonisolated public enum UpdateCheckSchedule: String, Sendable, CaseIterable {
    case off, every6Hours, daily, weekly

    /// Seconds between automatic checks; `nil` when off.
    public var interval: TimeInterval? {
        switch self {
        case .off: nil
        case .every6Hours: 21_600
        case .daily: 86_400
        case .weekly: 604_800
        }
    }
}

/// The system services the update checker depends on, replaceable in tests.
nonisolated public struct UpdateClient: Sendable {
    /// The latest published release; `nil` when the lookup failed.
    public var fetchLatest: @Sendable () async -> AppRelease?
    public var now: @Sendable () -> Date

    public init(fetchLatest: @escaping @Sendable () async -> AppRelease?, now: @escaping @Sendable () -> Date) {
        self.fetchLatest = fetchLatest
        self.now = now
    }

    /// GitHub's latest release, the one the website and the Homebrew cask point to.
    static let latestURL = URL(string: "https://api.github.com/repos/alvaldes/jump/releases/latest")!

    public static let live = UpdateClient(
        fetchLatest: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            var request = URLRequest(url: latestURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return UpdateChecker.release(fromGitHub: data)
        },
        now: { Date() }
    )
}

/// Looks for a newer JUMP on GitHub Releases: at launch and then on the
/// schedule, or when asked. A newer version shows in the menu bar menu and in
/// Settings; JUMP posts no notifications.
///
/// JUMP is not notarized, so it never installs anything itself: macOS would
/// block the downloaded app. It links to the release page instead.
@Observable
public final class UpdateChecker {
    /// A newer release than the running one, from the last successful lookup.
    public private(set) var available: AppRelease?
    public private(set) var isChecking = false
    /// When the last lookup finished, successful or not.
    public private(set) var lastCheck: Date?
    public private(set) var lastCheckFailed = false

    public let currentVersion: String

    /// Read at each check, so a change in Settings applies right away.
    private let schedule: () -> UpdateCheckSchedule
    private let client: UpdateClient

    public init(currentVersion: String, schedule: @escaping () -> UpdateCheckSchedule, client: UpdateClient = .live) {
        self.currentVersion = currentVersion
        self.schedule = schedule
        self.client = client
    }

    /// Checks every hour whether the schedule is due, so a Mac that slept still checks soon after waking.
    public func run() async {
        while !Task.isCancelled {
            await checkIfDue()
            try? await Task.sleep(for: .seconds(60 * 60))
        }
    }

    /// The automatic check: only when on and the schedule's interval after the last one.
    public func checkIfDue() async {
        guard let interval = schedule().interval else { return }
        if let lastCheck, client.now().timeIntervalSince(lastCheck) < interval { return }
        await lookUp()
    }

    /// Asked for in Settings; works even when automatic checks are off.
    public func checkNow() async {
        await lookUp()
    }

    /// Looks up the latest release and keeps it when it is newer than this one.
    private func lookUp() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let latest = await client.fetchLatest()
        lastCheck = client.now()
        lastCheckFailed = latest == nil
        guard let latest else { return }
        available = Self.isNewer(latest.version, than: currentVersion) ? latest : nil
    }

    /// Compares dotted numeric versions ("1.10.0" > "1.9.0"); a missing part counts as 0.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidate = numbers(candidate), let current = numbers(current) else { return false }
        for index in 0..<max(candidate.count, current.count) {
            let new = index < candidate.count ? candidate[index] : 0
            let old = index < current.count ? current[index] : 0
            if new != old { return new > old }
        }
        return false
    }

    private nonisolated static func numbers(_ version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") ? version.dropFirst() : Substring(version)
        let parts = trimmed.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }

    /// The release in GitHub's `releases/latest` answer; drafts and prereleases don't count.
    nonisolated static func release(fromGitHub data: Data) -> AppRelease? {
        struct Payload: Decodable {
            var tag_name: String
            var html_url: URL
            var draft: Bool?
            var prerelease: Bool?
            var body: String?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true else { return nil }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return AppRelease(version: version, pageURL: payload.html_url,
                          highlights: highlights(fromNotes: payload.body ?? ""))
    }

    /// The top-level bullets of release notes as plain text: no bold, code or
    /// link markup, and without the "by @user in <PR>" GitHub's generated notes add.
    nonisolated static func highlights(fromNotes notes: String) -> [String] {
        notes.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            guard line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") else { return nil }
            var text = String(line.dropFirst(2))
            text = text.replacingOccurrences(of: #" by @\S+ in https?://\S+$"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            for markup in ["**", "__", "`"] { text = text.replacingOccurrences(of: markup, with: "") }
            text = text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
    }
}
