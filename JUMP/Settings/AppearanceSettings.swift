import JumpKit
import SwiftUI

struct AppearanceSettings: View {
    let settings: JumpSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(title: "Appearance", subtitle: "How hints look. Changes apply to the next hints shown.")

            SettingsCard(title: "Preview", symbol: "eye") {
                HintPreview(appearance: settings.hintAppearance)
            }

            SettingsCard(title: "Theme", symbol: "swatchpalette") {
                HStack(spacing: 8) {
                    ForEach(HintTheme.allCases, id: \.self) { theme in
                        ThemeTile(theme: theme, isSelected: settings.hintAppearance.theme == theme) {
                            settings.setHintTheme(theme)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 18) {
                SettingsCard(title: "Size", symbol: "textformat.size") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(settings.hintAppearance.size) },
                                set: { settings.setHintSize(CGFloat($0)) }
                            ),
                            in: Double(HintAppearance.sizeRange.lowerBound)...Double(HintAppearance.sizeRange.upperBound),
                            step: 1
                        )
                        Text("\(Int(settings.hintAppearance.size)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                SettingsCard(title: "Liquid Glass", symbol: "drop", subtitle: "Regular is frosted, Clear is transparent.") {
                    Picker("", selection: Binding(
                        get: { settings.hintAppearance.glass },
                        set: { settings.setHintGlass($0) }
                    )) {
                        ForEach(HintGlass.allCases, id: \.self) { glass in
                            Text(glass.title).tag(glass)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            // The row takes the taller card's height and the shorter one stretches to it.
            .fixedSize(horizontal: false, vertical: true)

            SettingsCard(title: "Letter case", symbol: "textformat") {
                SettingRow(title: "Labels", detail: "Typing matches either way.") {
                    Picker("", selection: Binding(
                        get: { settings.hintAppearance.labelCase },
                        set: { settings.setHintLabelCase($0) }
                    )) {
                        ForEach(HintLabelCase.allCases, id: \.self) { labelCase in
                            Text(labelCase.title).tag(labelCase)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }
        }
    }
}
