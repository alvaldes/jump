/// A key press while hints are visible, already decoded from the raw event.
public enum HintKey: Sendable, Equatable {
    case character(Character)
    case backspace
    case escape
    case space
}

/// What the hint mode should do after a key press.
public enum HintInputResult: Sendable, Equatable {
    /// Keep waiting; only labels starting with this prefix stay visible.
    case filtering(String)
    /// The user typed this complete label.
    case matched(String)
    case cancelled
    /// Bring the hints underneath to the front.
    case rotate
    case ignored
}

/// Tracks the typed prefix and decides when a label is selected.
///
/// Labels are prefix-free, so a typed string can never both complete one
/// label and start another.
public struct HintInput: Sendable {
    public private(set) var typed = ""
    private let labels: [String]

    public init(labels: [String]) {
        self.labels = labels
    }

    public mutating func handle(_ key: HintKey) -> HintInputResult {
        switch key {
        case .escape:
            return .cancelled
        case .space:
            return .rotate
        case .backspace:
            guard !typed.isEmpty else { return .ignored }
            typed.removeLast()
            return .filtering(typed)
        case .character(let character):
            let candidate = typed + character.uppercased()
            if labels.contains(candidate) {
                return .matched(candidate)
            }
            // A typo exits instead of leaving the user stuck with no visible hint.
            guard labels.contains(where: { $0.hasPrefix(candidate) }) else { return .cancelled }
            typed = candidate
            return .filtering(typed)
        }
    }
}

/// What to do with the selected element, chosen by the modifier held while typing.
public enum HintAction: Sendable, Equatable {
    case press
    case rightClick
    case doubleClick
    case moveCursor

    public init(shift: Bool, command: Bool, option: Bool) {
        self = if shift { .rightClick } else if command { .doubleClick } else if option { .moveCursor } else { .press }
    }
}
