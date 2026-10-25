import KeyboardShortcuts
import SwiftUI

/// A key drawn as a physical keycap: lit from above, with a darker skirt
/// below its face.
struct Keycap: View {
    let label: String
    var minWidth: CGFloat = 26
    var isAccent = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isAccent ? Color.white : Color.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(minWidth: minWidth, minHeight: 24)
            .background(face, in: .rect(cornerRadius: Brand.keycapRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.keycapRadius)
                    .strokeBorder(Brand.hairline(scheme), lineWidth: 1)
            )
            // The skirt: the keycap's lower edge.
            .background(
                RoundedRectangle(cornerRadius: Brand.keycapRadius)
                    .fill(scheme == .dark ? Color.black.opacity(0.55) : Color.black.opacity(0.14))
                    .offset(y: 2)
            )
            .padding(.bottom, 2)
    }

    private var face: LinearGradient {
        if isAccent {
            return LinearGradient(colors: [Brand.graphite.opacity(0.75), Brand.graphite], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            colors: scheme == .dark
                ? [Color(white: 0.30), Color(white: 0.22)]
                : [.white, Color(white: 0.92)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// A shortcut as a row of keycaps (⌃ ⌥ ⇧ ⌘ then the key).
struct ShortcutKeycaps: View {
    let shortcut: KeyboardShortcuts.Shortcut?

    var body: some View {
        HStack(spacing: 4) {
            if let shortcut {
                ForEach(Array(Self.keys(of: shortcut).enumerated()), id: \.offset) { _, key in
                    Keycap(label: key, minWidth: key.count > 1 ? 44 : 26)
                }
            } else {
                Text("Not set").foregroundStyle(.secondary)
            }
        }
    }

    static func keys(of shortcut: KeyboardShortcuts.Shortcut) -> [String] {
        let modifiers: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let symbols = modifiers.filter { shortcut.modifiers.contains($0.0) }.map(\.1)
        let key = shortcut.description.filter { !"⌃⌥⇧⌘".contains($0) }
        return symbols + [key.isEmpty ? "?" : key]
    }
}
