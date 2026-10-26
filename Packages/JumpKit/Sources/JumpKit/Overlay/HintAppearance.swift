import AppKit

/// Color scheme of the hint labels. Every theme keeps the same shape.
public nonisolated enum HintTheme: String, CaseIterable, Sendable {
    case dark, light, system, accent, classic

    public var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        case .accent: "Accent"
        case .classic: "Classic"
        }
    }

    /// - Parameters:
    ///   - isDark: Whether the overlay currently draws in a dark appearance
    ///     (only `system` depends on it).
    ///   - accent: The user's accent color (only `accent` depends on it).
    public func palette(isDark: Bool, accent: NSColor) -> HintPalette {
        switch self {
        case .dark:
            HintPalette(fill: NSColor(white: 0.08, alpha: 0.9), text: .white,
                        typed: NSColor(white: 1, alpha: 0.4), border: NSColor(white: 1, alpha: 0.18))
        case .light:
            HintPalette(fill: NSColor(white: 1, alpha: 0.95), text: NSColor(white: 0.1, alpha: 1),
                        typed: NSColor(white: 0.1, alpha: 0.4), border: NSColor(white: 0, alpha: 0.15))
        case .system:
            (isDark ? HintTheme.dark : .light).palette(isDark: isDark, accent: accent)
        case .accent:
            Self.accentPalette(accent)
        case .classic:
            // Vimium's yellow labels.
            HintPalette(fill: NSColor(srgbRed: 1, green: 0.85, blue: 0.36, alpha: 1),
                        text: NSColor(srgbRed: 0.19, green: 0.15, blue: 0.02, alpha: 1),
                        typed: NSColor(srgbRed: 0.19, green: 0.15, blue: 0.02, alpha: 0.4),
                        border: NSColor(srgbRed: 0.76, green: 0.54, blue: 0.13, alpha: 1),
                        glassTint: NSColor(srgbRed: 1, green: 0.85, blue: 0.36, alpha: 0.6))
        }
    }

    /// Accent colors range from dark blue to yellow. White text (as on macOS
    /// buttons) is kept when darkening the accent a little makes it readable;
    /// light accents such as yellow get black text on a lightened accent.
    private static func accentPalette(_ accent: NSColor) -> HintPalette {
        let base = accent.usingColorSpace(.sRGB) ?? accent
        func white(_ fill: NSColor) -> HintPalette {
            HintPalette(fill: fill.withAlphaComponent(0.95), text: .white, typed: NSColor(white: 1, alpha: 0.45),
                        border: NSColor(white: 1, alpha: 0.25), glassTint: fill.withAlphaComponent(0.6))
        }
        func black(_ fill: NSColor) -> HintPalette {
            HintPalette(fill: fill.withAlphaComponent(0.95), text: .black, typed: NSColor(white: 0, alpha: 0.45),
                        border: NSColor(white: 0, alpha: 0.2), glassTint: fill.withAlphaComponent(0.6))
        }
        let steps = stride(from: 0.0, through: 1.0, by: 0.05)
        if let readable = steps.prefix(8).lazy
            .map({ white(base.blended(withFraction: $0, of: .black) ?? base) })
            .first(where: { $0.textContrast >= minimumContrast }) {
            return readable
        }
        return steps.lazy
            .map { black(base.blended(withFraction: $0, of: .white) ?? base) }
            .first { $0.textContrast >= minimumContrast } ?? black(.white)
    }

    /// WCAG AA for normal text.
    static let minimumContrast: CGFloat = 4.5
}

/// Colors used to draw one hint label.
public nonisolated struct HintPalette: Equatable {
    public let fill: NSColor
    public let text: NSColor
    /// Already typed characters.
    public let typed: NSColor
    public let border: NSColor
    /// Liquid Glass tint. Dark and light glass need none (the label color
    /// tells them apart); a strong tint would hide the glass.
    public var glassTint: NSColor? = nil

    /// WCAG contrast ratio of the text against the fill, in the worst case of
    /// whatever lies behind a translucent fill (black or white).
    var textContrast: CGFloat {
        let text = Self.luminance(of: text, over: .black)
        return [NSColor.black, .white].map { backdrop in
            let fill = Self.luminance(of: fill, over: backdrop)
            return (max(text, fill) + 0.05) / (min(text, fill) + 0.05)
        }.min() ?? 1
    }

    private static func luminance(of color: NSColor, over backdrop: NSColor) -> CGFloat {
        guard let color = color.usingColorSpace(.sRGB), let backdrop = backdrop.usingColorSpace(.sRGB) else { return 0 }
        let alpha = color.alphaComponent
        func channel(_ value: CGFloat, _ behind: CGFloat) -> CGFloat {
            let mixed = value * alpha + behind * (1 - alpha)
            return mixed <= 0.03928 ? mixed / 12.92 : pow((mixed + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent, backdrop.redComponent)
            + 0.7152 * channel(color.greenComponent, backdrop.greenComponent)
            + 0.0722 * channel(color.blueComponent, backdrop.blueComponent)
    }
}

/// Liquid Glass for hint labels: off (drawn pills), regular (frosted) or
/// clear (transparent, bends what is behind it).
public nonisolated enum HintGlass: String, CaseIterable, Sendable {
    case off, regular, clear

    public var title: String {
        switch self {
        case .off: "Off"
        case .regular: "Regular"
        case .clear: "Clear"
        }
    }
}

/// Whether labels are drawn in upper or lower case. Only the drawing changes:
/// typing matches either way.
public nonisolated enum HintLabelCase: String, CaseIterable, Sendable {
    case upper, lower

    public var title: String {
        switch self {
        case .upper: "ABC"
        case .lower: "abc"
        }
    }
}

/// How hint labels look: theme, label size, the Liquid Glass option and the
/// letter case.
public nonisolated struct HintAppearance: Equatable, Sendable {
    public var theme: HintTheme
    /// Label font size in points; pills scale with it.
    public var size: CGFloat
    public var glass: HintGlass
    public var labelCase: HintLabelCase

    public init(theme: HintTheme, size: CGFloat, glass: HintGlass, labelCase: HintLabelCase = .upper) {
        self.theme = theme
        self.size = size
        self.glass = glass
        self.labelCase = labelCase
    }

    public static let standard = HintAppearance(theme: .dark, size: 11, glass: .off)
    public static let sizeRange: ClosedRange<CGFloat> = 7...20
}
