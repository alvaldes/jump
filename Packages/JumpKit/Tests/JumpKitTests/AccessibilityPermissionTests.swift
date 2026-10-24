import Synchronization
import Testing
@testable import JumpKit

/// Fake system trust state shared with the client closures.
private final class FakeSystem: Sendable {
    let trusted: Mutex<Bool>
    let promptCount = Mutex(0)
    let settingsOpenCount = Mutex(0)

    init(trusted: Bool) {
        self.trusted = Mutex(trusted)
    }

    func client(changes: AsyncStream<Void> = AsyncStream { $0.finish() }) -> AccessibilityClient {
        AccessibilityClient(
            isTrusted: { self.trusted.withLock { $0 } },
            requestTrust: {
                self.promptCount.withLock { $0 += 1 }
                return self.trusted.withLock { $0 }
            },
            openSystemSettings: { self.settingsOpenCount.withLock { $0 += 1 } },
            trustChanges: { changes }
        )
    }
}

@Suite("AccessibilityPermission")
struct AccessibilityPermissionTests {
    @Test(arguments: [true, false])
    func initialStateReflectsSystemTrust(trusted: Bool) {
        let system = FakeSystem(trusted: trusted)
        let permission = AccessibilityPermission(client: system.client())
        #expect(permission.isTrusted == trusted)
    }

    @Test func requestPromptsAndUpdatesState() {
        let system = FakeSystem(trusted: false)
        let permission = AccessibilityPermission(client: system.client())

        system.trusted.withLock { $0 = true }
        permission.request()

        #expect(system.promptCount.withLock { $0 } == 1)
        #expect(permission.isTrusted)
    }

    @Test func requestDoesNotPromptWhenAlreadyTrusted() {
        let system = FakeSystem(trusted: true)
        let permission = AccessibilityPermission(client: system.client())

        permission.request()

        #expect(system.promptCount.withLock { $0 } == 0)
    }

    @Test func refreshPicksUpRevokedTrust() {
        let system = FakeSystem(trusted: true)
        let permission = AccessibilityPermission(client: system.client())

        system.trusted.withLock { $0 = false }
        permission.refresh()

        #expect(!permission.isTrusted)
    }

    @Test func openSystemSettingsDelegatesToClient() {
        let system = FakeSystem(trusted: false)
        let permission = AccessibilityPermission(client: system.client())

        permission.openSystemSettings()

        #expect(system.settingsOpenCount.withLock { $0 } == 1)
    }

    @Test func monitorUpdatesStateOnTrustChange() async {
        let system = FakeSystem(trusted: false)
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let permission = AccessibilityPermission(client: system.client(changes: changes))

        let monitoring = Task { await permission.monitor() }
        system.trusted.withLock { $0 = true }
        continuation.yield()
        continuation.finish()
        await monitoring.value

        #expect(permission.isTrusted)
    }
}
