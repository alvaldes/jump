import JumpKit
import SwiftUI

/// A sample window with hints drawn in the chosen appearance, so changes are
/// visible before the next hotkey.
struct HintPreview: View {
    let appearance: HintAppearance

    @Environment(\.colorScheme) private var scheme

    private let samples: [(label: String, x: CGFloat, y: CGFloat)] = [
        ("SA", 0.18, 0.30), ("SD", 0.52, 0.30), ("SF", 0.80, 0.30),
        ("DA", 0.30, 0.62), ("DS", 0.66, 0.62), ("F", 0.48, 0.86),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                window
                ForEach(samples, id: \.label) { sample in
                    pill(sample.label)
                        .position(x: proxy.size.width * sample.x, y: proxy.size.height * sample.y)
                }
            }
        }
        .frame(height: 170)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.hairline(scheme)))
    }

    /// A fake app window: title bar, sidebar and content lines.
    private var window: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.3), Color.orange.opacity(0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.8)).frame(width: 7, height: 7) }
                    Spacer()
                }
                .padding(8)
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.18)).frame(width: 70)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(0..<6, id: \.self) { row in
                            Capsule().fill(.white.opacity(0.25)).frame(width: CGFloat(200 - row * 22), height: 6)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private func pill(_ label: String) -> some View {
        let palette = appearance.theme.palette(isDark: scheme == .dark, accent: .controlAccentColor)
        let text = Text(label)
            .font(.system(size: appearance.size, weight: .semibold, design: .monospaced))
            .kerning(0.6 * appearance.size / 11)
            .foregroundStyle(Color(nsColor: palette.text))
            .padding(.horizontal, 6 * appearance.size / 11)
            .padding(.vertical, 2.5 * appearance.size / 11)
        switch appearance.glass {
        case .off:
            text
                .background(Color(nsColor: palette.fill), in: .capsule)
                .overlay(Capsule().strokeBorder(Color(nsColor: palette.border)))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        case .regular, .clear:
            text.glassEffect(
                (appearance.glass == .clear ? Glass.clear : Glass.regular)
                    .tint(palette.glassTint.map { Color(nsColor: $0) }),
                in: .capsule
            )
        }
    }
}

/// One theme as a tile: its name over a sample pill.
struct ThemeTile: View {
    let theme: HintTheme
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = theme.palette(isDark: scheme == .dark, accent: .controlAccentColor)
        Button(action: action) {
            VStack(spacing: 8) {
                Text("JU")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: palette.text))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(nsColor: palette.fill), in: .capsule)
                    .overlay(Capsule().strokeBorder(Color(nsColor: palette.border)))
                Text(theme.title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Brand.cardWash(scheme), in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.primary.opacity(0.7) : Brand.hairline(scheme),
                                  lineWidth: isSelected ? 1.5 : 1)
            )
            .overlay(alignment: .bottom) {
                if isSelected { HomingBump().padding(.bottom, 4) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
