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

/// What to do with the selected element, chosen by the modifier held while typing
/// (see `ActionModifiers`).
public enum HintAction: Sendable, Equatable {
    case press
    case rightClick
    case doubleClick
    case moveCursor
}

/// A modifier that can choose a `HintAction`.
public enum ActionModifier: String, CaseIterable, Sendable {
    case shift
    case control
    case option
    case command

    public var symbol: String {
        switch self {
        case .shift: "⇧"
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        }
    }

    func isHeld(in press: KeyPress) -> Bool {
        switch self {
        case .shift: press.shift
        case .control: press.control
        case .option: press.option
        case .command: press.command
        }
    }
}

/// Which modifier chooses each action other than a plain press. Every action
/// has its own modifier; one left over does nothing.
public struct ActionModifiers: Equatable, Sendable {
    /// In order of precedence when several modifiers are held.
    public static let actions: [HintAction] = [.rightClick, .doubleClick, .moveCursor]
    public static let standard = ActionModifiers(rightClick: .shift, doubleClick: .command, moveCursor: .option)!

    private var modifiers: [ActionModifier]

    /// `nil` when two actions share a modifier.
    public init?(rightClick: ActionModifier, doubleClick: ActionModifier, moveCursor: ActionModifier) {
        let modifiers = [rightClick, doubleClick, moveCursor]
        guard Set(modifiers).count == modifiers.count else { return nil }
        self.modifiers = modifiers
    }

    /// `nil` for `.press`, which needs no modifier.
    public func modifier(for action: HintAction) -> ActionModifier? {
        Self.actions.firstIndex(of: action).map { modifiers[$0] }
    }

    /// Gives `modifier` to `action`; the action that had it takes `action`'s old one.
    public mutating func assign(_ modifier: ActionModifier, to action: HintAction) {
        guard let index = Self.actions.firstIndex(of: action) else { return }
        if let holder = modifiers.firstIndex(of: modifier) {
            modifiers[holder] = modifiers[index]
        }
        modifiers[index] = modifier
    }

    public func action(for press: KeyPress) -> HintAction {
        zip(Self.actions, modifiers).first { $0.1.isHeld(in: press) }?.0 ?? .press
    }
}
