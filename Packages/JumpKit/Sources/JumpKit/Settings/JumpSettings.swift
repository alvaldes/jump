import Foundation
import Observation

/// User preferences, persisted in `UserDefaults`.
///
/// The activation shortcut is stored by KeyboardShortcuts and launch at login
/// by the system (`SMAppService`), so they are not duplicated here.
@Observable
public final class JumpSettings {
    public private(set) var hintCharacters: String
    public private(set) var hintAppearance: HintAppearance

    private let defaults: UserDefaults

    private enum Key {
        static let hintCharacters = "hintCharacters"
        static let hintTheme = "hintTheme"
        static let hintSize = "hintSize"
        static let hintGlass = "hintGlass"
    }

    /// Labels need at least two characters to tell elements apart.
    static let minimumHintCharacters = 2

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Key.hintCharacters).flatMap(Self.normalized)
        self.hintCharacters = stored ?? HintLabels.defaultCharacters
        self.hintAppearance = Self.storedAppearance(in: defaults)
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

    public func setHintTheme(_ theme: HintTheme) {
        hintAppearance.theme = theme
        defaults.set(theme.rawValue, forKey: Key.hintTheme)
    }

    /// Stores the label size rounded to whole points and kept within
    /// `HintAppearance.sizeRange`.
    public func setHintSize(_ size: CGFloat) {
        let range = HintAppearance.sizeRange
        hintAppearance.size = min(max(size.rounded(), range.lowerBound), range.upperBound)
        defaults.set(Double(hintAppearance.size), forKey: Key.hintSize)
    }

    public func setHintGlass(_ glass: HintGlass) {
        hintAppearance.glass = glass
        defaults.set(glass.rawValue, forKey: Key.hintGlass)
    }

    /// Each stored value that is missing or invalid falls back to its default.
    private static func storedAppearance(in defaults: UserDefaults) -> HintAppearance {
        let standard = HintAppearance.standard
        let theme = defaults.string(forKey: Key.hintTheme).flatMap(HintTheme.init(rawValue:))
        let size = (defaults.object(forKey: Key.hintSize) as? Double).map { CGFloat($0) }
            .flatMap { HintAppearance.sizeRange.contains($0) ? $0 : nil }
        let glass = defaults.string(forKey: Key.hintGlass).flatMap(HintGlass.init(rawValue:))
        return HintAppearance(theme: theme ?? standard.theme, size: size ?? standard.size, glass: glass ?? standard.glass)
    }

    static func normalized(_ input: String) -> String? {
        var seen = Set<Character>()
        let characters = input.lowercased().filter { $0.isASCII && $0.isLetter && seen.insert($0).inserted }
        return characters.count >= minimumHintCharacters ? characters : nil
    }
}
