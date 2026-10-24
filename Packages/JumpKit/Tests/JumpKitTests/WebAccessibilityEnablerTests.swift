import Testing
@testable import JumpKit

/// Records attribute writes and answers like a real app would.
private final class FakeApps {
    /// Attributes each pid accepts.
    var supported: [Int32: Set<String>] = [:]
    var writes: [(pid: Int32, attribute: String, value: Bool)] = []

    var setter: WebAccessibilityEnabler.AttributeSetter {
        { pid, attribute, value in
            self.writes.append((pid, attribute, value))
            return self.supported[pid, default: []].contains(attribute)
        }
    }
}

@Suite("WebAccessibilityEnabler")
struct WebAccessibilityEnablerTests {
    @Test func electronAppsGetManualAccessibility() {
        let apps = FakeApps()
        apps.supported[10] = ["AXManualAccessibility"]
        let enabler = WebAccessibilityEnabler(setAttribute: apps.setter)

        enabler.enable(pid: 10, bundleIdentifier: "md.obsidian")

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility"])
        #expect(apps.writes.allSatisfy { write in write.value })
    }

    @Test func chromiumBrowsersFallBackToEnhancedUserInterface() {
        let apps = FakeApps()
        apps.supported[20] = ["AXEnhancedUserInterface"]
        let enabler = WebAccessibilityEnabler(setAttribute: apps.setter)

        enabler.enable(pid: 20, bundleIdentifier: "com.google.Chrome")

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility", "AXEnhancedUserInterface"])
    }

    @Test func otherAppsNeverGetEnhancedUserInterface() {
        // It breaks window animations and window managers, so only browsers that need it get it.
        let apps = FakeApps()
        apps.supported[30] = ["AXEnhancedUserInterface"]
        let enabler = WebAccessibilityEnabler(setAttribute: apps.setter)

        enabler.enable(pid: 30, bundleIdentifier: "com.apple.finder")

        #expect(apps.writes.map(\.attribute) == ["AXManualAccessibility"])
    }

    @Test func eachAppIsHandledOnce() {
        let apps = FakeApps()
        let enabler = WebAccessibilityEnabler(setAttribute: apps.setter)

        enabler.enable(pid: 40, bundleIdentifier: "com.apple.finder")
        enabler.enable(pid: 40, bundleIdentifier: "com.apple.finder")

        #expect(apps.writes.count == 1)
    }

    @Test func restoreTurnsOffOnlyWhatWasTurnedOn() {
        let apps = FakeApps()
        apps.supported[10] = ["AXManualAccessibility"]
        apps.supported[20] = ["AXEnhancedUserInterface"]
        let enabler = WebAccessibilityEnabler(setAttribute: apps.setter)
        enabler.enable(pid: 10, bundleIdentifier: "md.obsidian")
        enabler.enable(pid: 20, bundleIdentifier: "com.google.Chrome")
        enabler.enable(pid: 30, bundleIdentifier: "com.apple.finder")
        apps.writes.removeAll()

        enabler.restoreAll()

        let restored = apps.writes.sorted { $0.pid < $1.pid }
        #expect(restored.map(\.pid) == [10, 20])
        #expect(restored.map(\.attribute) == ["AXManualAccessibility", "AXEnhancedUserInterface"])
        #expect(restored.allSatisfy { !$0.value })
    }

    @Test func quitAppsAreForgottenSoAReusedPidIsHandledAgain() {
        let apps = FakeApps()
        apps.supported[10] = ["AXManualAccessibility"]
        let enabler = WebAccessibilityEnabler(setAttribute: apps.setter)
        enabler.enable(pid: 10, bundleIdentifier: "md.obsidian")

        enabler.forget(pid: 10)
        enabler.restoreAll()
        #expect(apps.writes.count == 1, "nothing restored for an app that quit")

        enabler.enable(pid: 10, bundleIdentifier: "md.obsidian")
        #expect(apps.writes.count == 2, "a new app with the same pid is enabled")
    }
}
