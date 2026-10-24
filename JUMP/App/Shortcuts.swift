import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Shows hints for the focused window.
    static let activateHints = Self("activateHints", initial: .init(.space, modifiers: [.command, .shift]))
}
