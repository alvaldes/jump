/// What a key does in text search mode.
public enum SearchCommand: Sendable, Equatable {
    /// The query changed; carries the new query.
    case edited(String)
    case next
    case previous
    case jump(HintAction)
    case cancel
    case ignored
}

/// Edits the query and decodes navigation keys while the search box is open.
public struct SearchInput: Sendable {
    public private(set) var query = ""

    public init() {}

    public mutating func handle(_ press: KeyPress) -> SearchCommand {
        switch press.keyCode {
        case KeyPress.KeyCode.escape:
            return .cancel
        case KeyPress.KeyCode.returnKey, KeyPress.KeyCode.keypadEnter:
            // Same modifiers as hints: Shift right-clicks, ⌘ double-clicks, ⌥ moves the pointer.
            return .jump(HintAction(shift: press.shift, command: press.command, option: press.option))
        case KeyPress.KeyCode.tab:
            return press.shift ? .previous : .next
        case KeyPress.KeyCode.delete:
            guard !query.isEmpty else { return .ignored }
            query.removeLast()
            return .edited(query)
        default:
            // ⌘ and ⌃ are app shortcuts; ⌥ only chooses the jump action, so it still
            // types. What the layout produced goes in: `@` for ⌥2 on a Spanish layout,
            // and nothing for a dead key (the Spanish accent key), never its base character.
            let text = press.typedCharacters
            guard !press.command, !press.control, Self.isPrintable(text) else { return .ignored }
            query += text
            return .edited(query)
        }
    }

    /// Arrow and function keys arrive as private-use characters.
    private static func isPrintable(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            $0.properties.generalCategory != .control && $0.properties.generalCategory != .privateUse
        }
    }
}
