import CoreGraphics

/// Waits for the user to let go of the modifiers that chose an action.
///
/// Synthesized clicks are posted at the HID level, where the system adds the
/// modifiers still physically held: a double click chosen with ⌘ would reach
/// Finder as ⌘-double-click (open in a new tab).
public nonisolated enum ModifierRelease {
    static let actionModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    static func holdsModifiers(_ flags: CGEventFlags) -> Bool {
        !flags.intersection(actionModifiers).isEmpty
    }

    /// Returns `true` once no action modifier is held, `false` after `timeout`
    /// (a key held for good must not block the action forever).
    @discardableResult
    static func wait(
        timeout: Duration = .seconds(1),
        poll: Duration = .milliseconds(10),
        readFlags: @Sendable () -> CGEventFlags = { CGEventSource.flagsState(.hidSystemState) },
        sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Bool {
        let attempts = Int(timeout / poll)
        for attempt in 0...attempts {
            if !holdsModifiers(readFlags()) { return true }
            if attempt < attempts { await sleep(poll) }
        }
        return false
    }
}
