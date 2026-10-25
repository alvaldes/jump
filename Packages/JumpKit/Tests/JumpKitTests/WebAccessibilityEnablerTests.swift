import Dispatch
import Synchronization
import Testing
@testable import JumpKit

/// Records attribute writes and answers like a real app would. Each test
/// awaits every call before reading, so access is never concurrent.
private nonisolated final class FakeApps: @unchecked Sendable {
    /// Attributes each pid accepts.
    nonisolated(unsafe) var supported: [Int32: Set<String>] = [:]
    /// Current attribute values that can be read back.
    nonisolated(unsafe) var values: [Int32: [String: Bool]] = [:]
    nonisolated(unsafe) var writes: [(pid: Int32, attribute: String, value: Bool)] = []

    var setter: WebAccessibilityEnabler.AttributeSetter {
        { pid, attribute, value in
            self.writes.append((pid, attribute, value))
            return self.supported[pid, default: []].contains(attribute)
        }
    }

    var reader: WebAccessibilityEnabler.AttributeReader {
        { pid, attribute in self.values[pid]?[attribute] }
    }

    @MainActor func enabler() -> WebAccessibilityEnabler {
        WebAccessibilityEnabler(setAttribute: setter, readAttribute: reader)
    }
}

/// Thread-safe write log for tests whose writes run while the test continues.
private final class WriteLog: Sendable {
    let writes = Mutex<[(attribute: String, value: Bool)]>([])
}

@Suite("WebAccessibilityEnabler")
struct WebAccessibilityEnablerTests {
    @Test func enhancedUserInterfaceAlreadyOnIsLeftAlone() async {
        // VoiceOver (or another tool) turned it on: JUMP must not turn it off later.
        let apps = FakeApps()
        apps.supported[20] = ["AXEnhancedUserInterface"]
        apps.values[20] = ["AXEnhancedUserInterface": true]
        let enabler = apps.enabler()

        await enabler.enable(pid: 20, bundleIdentifier: "com.google.Chrome")
        enabler.restoreAll()

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility"])
    }

    @Test func electronAppsGetManualAccessibility() async {
        let apps = FakeApps()
        apps.supported[10] = ["AXManualAccessibility"]
        let enabler = apps.enabler()

        await enabler.enable(pid: 10, bundleIdentifier: "md.obsidian")

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility"])
        #expect(apps.writes.allSatisfy { write in write.value })
    }

    @Test func chromiumBrowsersFallBackToEnhancedUserInterface() async {
        let apps = FakeApps()
        apps.supported[20] = ["AXEnhancedUserInterface"]
        let enabler = apps.enabler()

        await enabler.enable(pid: 20, bundleIdentifier: "com.google.Chrome")

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility", "AXEnhancedUserInterface"])
    }

    @Test func otherAppsNeverGetEnhancedUserInterface() async {
        // It breaks window animations and window managers, so only browsers that need it get it.
        let apps = FakeApps()
        apps.supported[30] = ["AXEnhancedUserInterface"]
        let enabler = apps.enabler()

        await enabler.enable(pid: 30, bundleIdentifier: "com.apple.finder")

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility"])
    }

    @Test func eachAppIsHandledOnce() async {
        let apps = FakeApps()
        let enabler = apps.enabler()

        await enabler.enable(pid: 40, bundleIdentifier: "com.apple.finder")
        await enabler.enable(pid: 40, bundleIdentifier: "com.apple.finder")

        #expect(apps.writes.count == 1)
    }

    @Test func restoreTurnsOffOnlyWhatWasTurnedOn() async {
        let apps = FakeApps()
        apps.supported[10] = ["AXManualAccessibility"]
        apps.supported[20] = ["AXEnhancedUserInterface"]
        let enabler = apps.enabler()
        await enabler.enable(pid: 10, bundleIdentifier: "md.obsidian")
        await enabler.enable(pid: 20, bundleIdentifier: "com.google.Chrome")
        await enabler.enable(pid: 30, bundleIdentifier: "com.apple.finder")
        apps.writes.removeAll()

        enabler.restoreAll()

        let restored = apps.writes.sorted { $0.pid < $1.pid }
        #expect(restored.map(\.pid) == [10, 20])
        #expect(restored.map(\.attribute) == ["AXManualAccessibility", "AXEnhancedUserInterface"])
        #expect(restored.allSatisfy { !$0.value })
    }

    @Test func quitAppsAreForgottenSoAReusedPidIsHandledAgain() async {
        let apps = FakeApps()
        apps.supported[10] = ["AXManualAccessibility"]
        let enabler = apps.enabler()
        await enabler.enable(pid: 10, bundleIdentifier: "md.obsidian")

        enabler.forget(pid: 10)
        enabler.restoreAll()
        #expect(apps.writes.count == 1, "nothing restored for an app that quit")

        await enabler.enable(pid: 10, bundleIdentifier: "md.obsidian")
        #expect(apps.writes.count == 2, "a new app with the same pid is enabled")
    }

    @Test(arguments: [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "company.thebrowser.Browser",
    ])
    func everyKnownChromiumBrowserFallsBackToEnhancedUserInterface(bundleIdentifier: String) async {
        let apps = FakeApps()
        apps.supported[20] = ["AXEnhancedUserInterface"]
        let enabler = apps.enabler()

        await enabler.enable(pid: 20, bundleIdentifier: bundleIdentifier)

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility", "AXEnhancedUserInterface"])
        #expect(apps.writes.allSatisfy { write in write.value })
    }

    @Test func chromiumBrowsersThatAcceptManualAccessibilityKeepEnhancedUserInterfaceOff() async {
        // Current Chromium honors the Electron switch, so the window-breaking one is not needed.
        let apps = FakeApps()
        apps.supported[20] = ["AXManualAccessibility", "AXEnhancedUserInterface"]
        let enabler = apps.enabler()

        await enabler.enable(pid: 20, bundleIdentifier: "com.google.Chrome")
        enabler.restoreAll()

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility", "AXManualAccessibility"])
        #expect(apps.writes.map(\.value) == [true, false])
    }

    @Test func appsWithoutABundleIdentifierAreNotTreatedAsBrowsers() async {
        let apps = FakeApps()
        apps.supported[50] = ["AXEnhancedUserInterface"]
        let enabler = apps.enabler()

        await enabler.enable(pid: 50, bundleIdentifier: nil)

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility"])
    }

    @Test func rejectedWritesAreNeitherRetriedNorRestored() async {
        let apps = FakeApps()
        let enabler = apps.enabler()

        await enabler.enable(pid: 20, bundleIdentifier: "com.google.Chrome")
        await enabler.enable(pid: 20, bundleIdentifier: "com.google.Chrome")
        enabler.restoreAll()

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility", "AXEnhancedUserInterface"])
        #expect(apps.writes.allSatisfy { write in write.value })
    }

    @Test func restoringTwiceTurnsEachAttributeOffOnce() async {
        let apps = FakeApps()
        apps.supported[10] = ["AXManualAccessibility"]
        let enabler = apps.enabler()
        await enabler.enable(pid: 10, bundleIdentifier: "md.obsidian")

        enabler.restoreAll()
        enabler.restoreAll()

        #expect(apps.writes.map(\.value) == [true, false])
    }

    @Test func anAppThatQuitsWhileBeingEnabledIsNeverRestored() async {
        // The writes run off the main actor; the app can quit (and be forgotten) meanwhile.
        let log = WriteLog()
        let (entered, enteredContinuation) = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let enabler = WebAccessibilityEnabler(
            setAttribute: { _, attribute, value in
                log.writes.withLock { $0.append((attribute, value)) }
                if value {
                    enteredContinuation.yield()
                    release.wait()
                }
                return true
            },
            readAttribute: { _, _ in nil }
        )

        let enabling = Task { await enabler.enable(pid: 10, bundleIdentifier: "md.obsidian") }
        for await _ in entered { break }
        enabler.forget(pid: 10)
        release.signal()
        await enabling.value
        enabler.restoreAll()

        #expect(log.writes.withLock { $0.map(\.attribute) } == ["AXManualAccessibility"])
        #expect(log.writes.withLock { $0.map(\.value) } == [true])
    }
}
