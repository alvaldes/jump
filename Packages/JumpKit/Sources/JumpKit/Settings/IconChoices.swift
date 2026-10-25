/// Menu bar icon; all are template images in the app's asset catalog.
public nonisolated enum MenuBarIcon: String, CaseIterable, Sendable {
    case keycap, outline, filled

    public var title: String {
        switch self {
        case .keycap: "Keycap"
        case .outline: "Outline"
        case .filled: "Filled"
        }
    }

    public var imageName: String {
        switch self {
        case .keycap: "MenuBarIconKeycap"
        case .outline: "MenuBarIconOutline"
        case .filled: "MenuBarIconFilled"
        }
    }
}

/// Dock tile icon while JUMP shows in the Dock. Finder, Launchpad and
/// Spotlight always show the official icon.
public nonisolated enum AppIconChoice: String, CaseIterable, Sendable {
    case official, glyph

    public var title: String {
        switch self {
        case .official: "Official"
        case .glyph: "Glyph"
        }
    }

    /// The alternate icon in the asset catalog, or `nil` for the bundle's own icon.
    public var imageName: String? {
        switch self {
        case .official: nil
        case .glyph: "AppIconGlyph"
        }
    }
}
