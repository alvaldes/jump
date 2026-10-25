import SwiftUI

/// JUMP's visual language, taken from its icon: a glass keycap in graphite,
/// an embossed J and the homing bump of a home-row key.
enum Brand {
    /// Graphite of the icon's keycap face.
    static let graphite = Color(red: 0.17, green: 0.19, blue: 0.21)

    static let cardRadius: CGFloat = 16
    static let keycapRadius: CGFloat = 7

    /// Thin card border, like the keycap's beveled edge.
    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.09) : .black.opacity(0.08)
    }

    /// A soft top-lit wash, as light falls on the keycap.
    static func cardWash(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [.white.opacity(0.06), .white.opacity(0.015)]
                : [.white.opacity(0.85), .white.opacity(0.55)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// The window's backdrop: graphite fading in from the sidebar.
    static func backdrop(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [graphite.opacity(0.55), Color(nsColor: .windowBackgroundColor)]
                : [Color(nsColor: .windowBackgroundColor), Color(white: 0.93)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// The homing bump under F and J: marks the selected item.
struct HomingBump: View {
    var body: some View {
        Capsule()
            .fill(.primary.opacity(0.85))
            .frame(width: 14, height: 3)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
    }
}
