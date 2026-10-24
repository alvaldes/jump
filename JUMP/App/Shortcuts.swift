import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Shows hints for the focused window.
    static let activateHints = Self("activateHints", initial: .init(.space, modifiers: [.command, .shift]))

    /// Enters scroll mode on the focused window.
    static let activateScroll = Self("activateScroll", initial: .init(.j, modifiers: [.command, .shift]))
}
