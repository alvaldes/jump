import Foundation
import Synchronization
import Testing
@testable import JumpKit

private let page = URL(string: "https://github.com/alvaldes/jump/releases/tag/v1.2.0")!

/// A GitHub that answers with `latest` and counts lookups.
private final class FakeGitHub: Sendable {
    let latest: Mutex<AppRelease?>
    let now = Mutex(Date(timeIntervalSince1970: 1_000))
    let fetches = Mutex(0)

    init(latest: AppRelease?) {
        self.latest = Mutex(latest)
    }

    var client: UpdateClient {
        UpdateClient(
            fetchLatest: {
                self.fetches.withLock { $0 += 1 }
                return self.latest.withLock { $0 }
            },
            now: { self.now.withLock { $0 } }
        )
    }

    func advance(by seconds: TimeInterval) {
        now.withLock { $0 += seconds }
    }

    var fetchCount: Int { fetches.withLock { $0 } }
}

@Suite("Version comparison")
struct VersionComparisonTests {
    @Test(arguments: [
        ("1.0.1", "1.0.0"),
        ("1.10.0", "1.9.0"),
        ("v1.1", "1.0.9"),
        ("2.0.0", "1.99.99"),
    ])
    func newer(candidate: String, current: String) {
        #expect(UpdateChecker.isNewer(candidate, than: current))
    }

    @Test(arguments: [
        ("1.0", "1.0.0"),
        ("1.0.0", "1.0.0"),
        ("0.9.0", "1.0.0"),
        ("latest", "1.0.0"),
        ("1.1.0", "?"),
    ])
    func notNewer(candidate: String, current: String) {
        #expect(!UpdateChecker.isNewer(candidate, than: current))
    }
}

@Suite("GitHub release parsing")
struct GitHubReleaseParsingTests {
    @Test func readsTheTagAndPage() {
        let json = #"{"tag_name":"v1.2.0","html_url":"\#(page.absoluteString)","draft":false,"prerelease":false}"#
        #expect(UpdateChecker.release(fromGitHub: Data(json.utf8)) == AppRelease(version: "1.2.0", pageURL: page))
    }

    @Test func readsTheHighlightsFromTheNotes() throws {
        let notes = "## What's new\n\n- **Excluded apps** in Settings\n- Faster [text search](https://x.dev)\n\n**Full Changelog**: https://x"
        let json = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v1.2.0", "html_url": page.absoluteString, "body": notes,
        ])
        #expect(UpdateChecker.release(fromGitHub: json)?.highlights == ["Excluded apps in Settings", "Faster text search"])
    }

    @Test(arguments: [
        #"{"tag_name":"v1.2.0","html_url":"https://github.com/x","draft":true,"prerelease":false}"#,
        #"{"tag_name":"v1.2.0","html_url":"https://github.com/x","draft":false,"prerelease":true}"#,
        #"{"html_url":"https://github.com/x"}"#,
        #"{"message":"Not Found"}"#,
        "not json",
    ])
    func ignoresAnythingElse(json: String) {
        #expect(UpdateChecker.release(fromGitHub: Data(json.utf8)) == nil)
    }
}

@Suite("Release highlights")
struct ReleaseHighlightsTests {
    @Test func takesTopLevelBulletsWithoutMarkdown() {
        let notes = """
        ## What's new
        - **Bold** and `code`
        * Star bullet
          - Nested detail
        Plain paragraph
        + Plus bullet
        """
        #expect(UpdateChecker.highlights(fromNotes: notes) == ["Bold and code", "Star bullet", "Plus bullet"])
    }

    @Test func dropsGitHubsGeneratedAuthorAndLink() {
        let notes = "- Add update notices by @alvaldes in https://github.com/alvaldes/jump/pull/12"
        #expect(UpdateChecker.highlights(fromNotes: notes) == ["Add update notices"])
    }

    @Test func noBulletsMeansNoHighlights() {
        #expect(UpdateChecker.highlights(fromNotes: "**Full Changelog**: https://x").isEmpty)
    }
}

@Suite("Update check schedule")
struct UpdateCheckScheduleTests {
    @Test func intervals() {
        #expect(UpdateCheckSchedule.off.interval == nil)
        #expect(UpdateCheckSchedule.every6Hours.interval == 21_600)
        #expect(UpdateCheckSchedule.daily.interval == 86_400)
        #expect(UpdateCheckSchedule.weekly.interval == 604_800)
    }

    @Test func dailyByDefaultAndPersisted() {
        let name = "UpdateCheckScheduleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = JumpSettings(defaults: defaults)
        #expect(settings.updateCheckSchedule == .daily)

        settings.setUpdateCheckSchedule(.weekly)

        #expect(settings.updateCheckSchedule == .weekly)
        #expect(JumpSettings(defaults: defaults).updateCheckSchedule == .weekly)
    }
}

@Suite("UpdateChecker")
struct UpdateCheckerTests {
    private let newer = AppRelease(version: "1.2.0", pageURL: page, highlights: ["Excluded apps", "Click modifiers"])

    private func checker(_ fake: FakeGitHub, schedule: UpdateCheckSchedule = .daily,
                         current: String = "1.0.0") -> UpdateChecker {
        UpdateChecker(currentVersion: current, schedule: { schedule }, client: fake.client)
    }

    @Test func findsANewerVersion() async {
        let fake = FakeGitHub(latest: newer)
        let sut = checker(fake)

        await sut.checkIfDue()

        #expect(sut.available == newer)
        #expect(!sut.lastCheckFailed)
    }

    @Test func staysEmptyWhenUpToDate() async {
        let fake = FakeGitHub(latest: AppRelease(version: "1.0.0", pageURL: page))
        let sut = checker(fake)

        await sut.checkIfDue()

        #expect(sut.available == nil)
        #expect(!sut.lastCheckFailed)
        #expect(sut.lastCheck != nil)
    }

    @Test(arguments: [UpdateCheckSchedule.every6Hours, .daily, .weekly])
    func checksAtMostOncePerInterval(schedule: UpdateCheckSchedule) async {
        let fake = FakeGitHub(latest: newer)
        let sut = checker(fake, schedule: schedule)

        await sut.checkIfDue()
        fake.advance(by: schedule.interval! - 60)
        await sut.checkIfDue()
        #expect(fake.fetchCount == 1)

        fake.advance(by: 60)
        await sut.checkIfDue()
        #expect(fake.fetchCount == 2)
    }

    @Test func doesNothingWhenTurnedOff() async {
        let fake = FakeGitHub(latest: newer)
        let sut = checker(fake, schedule: .off)

        await sut.checkIfDue()

        #expect(fake.fetchCount == 0)
        #expect(sut.available == nil)
        #expect(sut.lastCheck == nil)
    }

    @Test func checkNowWorksEvenWhenTurnedOff() async {
        let fake = FakeGitHub(latest: newer)
        let sut = checker(fake, schedule: .off)

        await sut.checkNow()

        #expect(sut.available == newer)
    }

    @Test func anEvenNewerVersionReplacesTheLastOne() async {
        let fake = FakeGitHub(latest: newer)
        let sut = checker(fake)
        await sut.checkIfDue()

        let latest = AppRelease(version: "1.3.0", pageURL: page)
        fake.latest.withLock { $0 = latest }
        fake.advance(by: UpdateCheckSchedule.daily.interval!)
        await sut.checkIfDue()

        #expect(sut.available == latest)
    }

    @Test func aFailedLookupIsReportedAndKeepsTheLastAnswer() async {
        let fake = FakeGitHub(latest: newer)
        let sut = checker(fake)
        await sut.checkNow()

        fake.latest.withLock { $0 = nil }
        await sut.checkNow()

        #expect(sut.lastCheckFailed)
        #expect(sut.available == newer)
    }
}
