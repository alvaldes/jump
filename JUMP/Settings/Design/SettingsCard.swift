import SwiftUI

/// A card in the 21st.dev style: a flat, top-lit surface with a hairline
/// border and a soft shadow (glass is kept for the hints themselves).
struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    var subtitle: String?
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(Brand.cardWash(scheme), in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.hairline(scheme)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.cardWash(scheme), in: .rect(cornerRadius: Brand.cardRadius))
        .background(Color(nsColor: .controlBackgroundColor).opacity(scheme == .dark ? 0.35 : 0.6),
                    in: .rect(cornerRadius: Brand.cardRadius))
        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.06), radius: 10, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: Brand.cardRadius)
                .strokeBorder(Brand.hairline(scheme), lineWidth: 1)
        )
    }
}

/// A label with an optional explanation on the left, its control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
    }
}

/// A status dot with a soft glow.
struct StatusDot: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
            .shadow(color: (isOn ? Color.green : Color.orange).opacity(0.7), radius: 4)
    }
}

/// Title block at the top of each pane.
struct PaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
