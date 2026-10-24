import Foundation
import Observation

/// User preferences, persisted in `UserDefaults`.
///
/// The activation shortcut is stored by KeyboardShortcuts and launch at login
/// by the system (`SMAppService`), so they are not duplicated here.
@Observable
public final class JumpSettings {
    public private(set) var hintCharacters: String

    private let defaults: UserDefaults

    private enum Key {
        static let hintCharacters = "hintCharacters"
    }

    /// Labels need at least two characters to tell elements apart.
    static let minimumHintCharacters = 2

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Key.hintCharacters).flatMap(Self.normalized)
        self.hintCharacters = stored ?? HintLabels.defaultCharacters
    }

    /// Stores the characters used for labels, lowercased, without duplicates or
    /// non-letters. Returns `false` and keeps the current value when fewer than
    /// two usable characters remain.
    @discardableResult
    public func setHintCharacters(_ input: String) -> Bool {
        guard let characters = Self.normalized(input) else { return false }
        hintCharacters = characters
        defaults.set(characters, forKey: Key.hintCharacters)
        return true
    }

    static func normalized(_ input: String) -> String? {
        var seen = Set<Character>()
        let characters = input.lowercased().filter { $0.isASCII && $0.isLetter && seen.insert($0).inserted }
        return characters.count >= minimumHintCharacters ? characters : nil
    }
}
