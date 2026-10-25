import JumpKit
import SwiftUI

struct AppearanceSettings: View {
    let settings: JumpSettings

    var body: some View {
        SettingsPane {
            Section {
                Picker("Hint theme:", selection: Binding(
                    get: { settings.hintAppearance.theme },
                    set: { settings.setHintTheme($0) }
                )) {
                    ForEach(HintTheme.allCases, id: \.self) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                LabeledContent("Hint size:") {
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
                Picker("Liquid Glass:", selection: Binding(
                    get: { settings.hintAppearance.glass },
                    set: { settings.setHintGlass($0) }
                )) {
                    ForEach(HintGlass.allCases, id: \.self) { glass in
                        Text(glass.title).tag(glass)
                    }
                }
                Text("Applies to the next hints shown. Regular glass is frosted, Clear is transparent; Accent and Classic tint it.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
