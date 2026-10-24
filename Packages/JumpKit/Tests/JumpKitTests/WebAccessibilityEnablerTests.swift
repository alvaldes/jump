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
}
