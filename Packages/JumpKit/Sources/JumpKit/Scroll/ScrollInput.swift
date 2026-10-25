public nonisolated enum ScrollDirection: Sendable, Equatable {
    case up, down, left, right
}

public enum ScrollCommand: Sendable, Equatable {
    /// Scroll continuously while the key is held.
    case scroll(ScrollDirection)
    /// Jump half of the scroll area.
    case halfPage(ScrollDirection)
    case top
    case bottom
    case nextArea
    case exit
}

/// A key press in scroll mode, already decoded from the raw event.
public enum ScrollKey: Sendable, Equatable {
    /// The typed character, case-sensitive (`G` differs from `g`).
    case character(Character)
    case tab
    case escape
}

extension ScrollKey {
    /// Decodes a typed letter so that only Shift makes it uppercase: with
    /// Caps Lock on, `j` must still scroll down and `g` must not act as `G`.
    public static func decode(_ character: Character, shift: Bool) -> ScrollKey {
        let base = Character(character.lowercased())
        return .character(shift ? Character(base.uppercased()) : base)
    }
}

public enum ScrollInputResult: Sendable, Equatable {
    case command(ScrollCommand)
    /// The first key of a sequence (`g`) is waiting for the next one.
    case pending
    case ignored
}

/// Maps Vim-style keys to scroll commands (Vimac's defaults).
public struct ScrollInput: Sendable {
    private var pendingG = false

    public init() {}

    public mutating func handle(_ key: ScrollKey) -> ScrollInputResult {
        let wasPendingG = pendingG
        pendingG = false
        switch key {
        case .tab:
            return .command(.nextArea)
        case .escape:
            return .command(.exit)
        case .character("g"):
            if wasPendingG { return .command(.top) }
            pendingG = true
            return .pending
        case .character(let character) where !wasPendingG:
            return Self.singleKeyCommands[character].map(ScrollInputResult.command) ?? .ignored
        case .character:
            // Anything but a second `g` cancels the sequence.
            return .ignored
        }
    }

    /// Drops a pending sequence (for example after a timeout).
    public mutating func reset() {
        pendingG = false
    }

    private static let singleKeyCommands: [Character: ScrollCommand] = [
        "h": .scroll(.left), "j": .scroll(.down), "k": .scroll(.up), "l": .scroll(.right),
        "d": .halfPage(.down), "u": .halfPage(.up), "G": .bottom,
    ]
}
