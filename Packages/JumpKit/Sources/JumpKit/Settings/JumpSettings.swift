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
    public private(set) var menuBarIcon: MenuBarIcon
    public private(set) var showInDock: Bool
    public private(set) var appIcon: AppIconChoice
    public private(set) var scrollSpeed: ScrollSpeed
    public private(set) var showsScrollOutline: Bool
    /// Text search falls back to recognizing the window's text on screen (OCR).
    public private(set) var recognizesScreenText: Bool
    /// Bundle identifiers of the apps where JUMP's shortcuts stay off, in the order they were added.
    public private(set) var excludedApps: [String]
    /// Which modifier, held while typing a label, chooses each click action.
    public private(set) var actionModifiers: ActionModifiers

    private let defaults: UserDefaults

    private enum Key {
        static let hintCharacters = "hintCharacters"
        static let hintTheme = "hintTheme"
        static let hintSize = "hintSize"
        static let hintGlass = "hintGlass"
        static let hintLabelCase = "hintLabelCase"
        static let scrollSpeed = "scrollSpeed"
        static let scrollOutline = "scrollOutline"
        static let menuBarIcon = "menuBarIcon"
        static let showInDock = "showInDock"
        static let appIcon = "appIcon"
        static let recognizeScreenText = "recognizeScreenText"
        static let excludedApps = "excludedApps"
        static let rightClickModifier = "rightClickModifier"
        static let doubleClickModifier = "doubleClickModifier"
        static let moveCursorModifier = "moveCursorModifier"
    }

    /// Labels need at least two characters to tell elements apart.
    static let minimumHintCharacters = 2

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Key.hintCharacters).flatMap(Self.normalized)
        self.hintCharacters = stored ?? HintLabels.defaultCharacters
        self.hintAppearance = Self.storedAppearance(in: defaults)
        self.menuBarIcon = defaults.string(forKey: Key.menuBarIcon).flatMap(MenuBarIcon.init(rawValue:)) ?? .keycap
        self.showInDock = defaults.object(forKey: Key.showInDock) as? Bool ?? false
        self.appIcon = defaults.string(forKey: Key.appIcon).flatMap(AppIconChoice.init(rawValue:)) ?? .official
        self.recognizesScreenText = defaults.object(forKey: Key.recognizeScreenText) as? Bool ?? false
        self.scrollSpeed = defaults.string(forKey: Key.scrollSpeed).flatMap(ScrollSpeed.init(rawValue:)) ?? .normal
        self.showsScrollOutline = defaults.object(forKey: Key.scrollOutline) as? Bool ?? true
        self.excludedApps = defaults.object(forKey: Key.excludedApps) as? [String] ?? []
        self.actionModifiers = Self.storedActionModifiers(in: defaults)
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

    public func setHintLabelCase(_ labelCase: HintLabelCase) {
        hintAppearance.labelCase = labelCase
        defaults.set(labelCase.rawValue, forKey: Key.hintLabelCase)
    }

    public func setScrollSpeed(_ speed: ScrollSpeed) {
        scrollSpeed = speed
        defaults.set(speed.rawValue, forKey: Key.scrollSpeed)
    }

    public func setShowsScrollOutline(_ shows: Bool) {
        showsScrollOutline = shows
        defaults.set(shows, forKey: Key.scrollOutline)
    }

    public func setMenuBarIcon(_ icon: MenuBarIcon) {
        menuBarIcon = icon
        defaults.set(icon.rawValue, forKey: Key.menuBarIcon)
    }

    public func setShowInDock(_ show: Bool) {
        showInDock = show
        defaults.set(show, forKey: Key.showInDock)
    }

    public func setAppIcon(_ icon: AppIconChoice) {
        appIcon = icon
        defaults.set(icon.rawValue, forKey: Key.appIcon)
    }

    public func setRecognizesScreenText(_ enabled: Bool) {
        recognizesScreenText = enabled
        defaults.set(enabled, forKey: Key.recognizeScreenText)
    }

    /// Turns JUMP's shortcuts off while this app is in front. Empty identifiers are ignored.
    public func excludeApp(_ bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty, !excludedApps.contains(bundleIdentifier) else { return }
        excludedApps.append(bundleIdentifier)
        defaults.set(excludedApps, forKey: Key.excludedApps)
    }

    public func includeApp(_ bundleIdentifier: String) {
        excludedApps.removeAll { $0 == bundleIdentifier }
        defaults.set(excludedApps, forKey: Key.excludedApps)
    }

    /// Apps without a bundle identifier cannot be listed, so they are never excluded.
    public func isExcluded(bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map(excludedApps.contains) ?? false
    }

    /// The action that used `modifier` takes this action's old one.
    public func setActionModifier(_ modifier: ActionModifier, for action: HintAction) {
        actionModifiers.assign(modifier, to: action)
        for (action, key) in Self.actionModifierKeys {
            defaults.set(actionModifiers.modifier(for: action)?.rawValue, forKey: key)
        }
    }

    private static let actionModifierKeys: [(HintAction, String)] = [
        (.rightClick, Key.rightClickModifier), (.doubleClick, Key.doubleClickModifier), (.moveCursor, Key.moveCursorModifier),
    ]

    /// A missing, invalid or repeated stored modifier restores the whole standard mapping.
    private static func storedActionModifiers(in defaults: UserDefaults) -> ActionModifiers {
        let stored = actionModifierKeys.map { action, key in
            defaults.string(forKey: key).flatMap(ActionModifier.init(rawValue:)) ?? ActionModifiers.standard.modifier(for: action)!
        }
        return ActionModifiers(rightClick: stored[0], doubleClick: stored[1], moveCursor: stored[2]) ?? .standard
    }

    /// Each stored value that is missing or invalid falls back to its default.
    private static func storedAppearance(in defaults: UserDefaults) -> HintAppearance {
        let standard = HintAppearance.standard
        let theme = defaults.string(forKey: Key.hintTheme).flatMap(HintTheme.init(rawValue:))
        let size = (defaults.object(forKey: Key.hintSize) as? Double).map { CGFloat($0).rounded() }
            .flatMap { HintAppearance.sizeRange.contains($0) ? $0 : nil }
        let glass = defaults.string(forKey: Key.hintGlass).flatMap(HintGlass.init(rawValue:))
        let labelCase = defaults.string(forKey: Key.hintLabelCase).flatMap(HintLabelCase.init(rawValue:))
        return HintAppearance(theme: theme ?? standard.theme, size: size ?? standard.size, glass: glass ?? standard.glass,
                              labelCase: labelCase ?? standard.labelCase)
    }

    static func normalized(_ input: String) -> String? {
        var seen = Set<Character>()
        let characters = input.lowercased().filter { $0.isASCII && $0.isLetter && seen.insert($0).inserted }
        return characters.count >= minimumHintCharacters ? characters : nil
    }
}
