import JumpKit
import SwiftUI

struct BehaviorSettings: View {
    let settings: JumpSettings
    let screenRecording: ScreenRecordingPermission
    let recognizer: ScreenTextRecognizer

    @State private var characters = ""
    @State private var charactersRejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader(title: "Behavior", subtitle: "How hints are labeled and how text search reads the screen.")

            SettingsCard(title: "Hint labels", symbol: "character.textbox",
                         subtitle: "Labels are built from these letters, first ones first.") {
                HStack(spacing: 4) {
                    ForEach(Array(settings.hintCharacters.uppercased().enumerated()), id: \.offset) { _, letter in
                        Keycap(label: String(letter))
                    }
                }
                HStack {
                    TextField("Hint characters", text: $characters)
                        .font(.body.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyCharacters)
                    Button("Apply", action: applyCharacters)
                    Button("Restore Default") {
                        characters = HintLabels.defaultCharacters
                        applyCharacters()
                    }
                }
                if charactersRejected {
                    Text("Use at least two different letters.").font(.caption).foregroundStyle(.red)
                }
            }

            SettingsCard(title: "Text search", symbol: "text.magnifyingglass") {
                SettingRow(title: "Recognize text on screen (OCR)",
                           detail: "For windows without readable text, such as terminals, PDFs and images. Needs Screen Recording.") {
                    Toggle("", isOn: Binding(
                        get: { settings.recognizesScreenText },
                        set: { setRecognizesScreenText($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                if settings.recognizesScreenText, !screenRecording.isGranted {
                    HStack(alignment: .top, spacing: 10) {
                        StatusDot(isOn: false).padding(.top, 5)
                        Text("Allow JUMP in Screen & System Audio Recording; until then text search uses Accessibility only. JUMP may need to be reopened.")
                            .font(.caption)
                        Spacer()
                        Button("Open Privacy Settings") { screenRecording.openPrivacySettings() }
                    }
                }
            }
        }
        .onAppear {
            characters = settings.hintCharacters
            screenRecording.refresh()
        }
    }

    /// Turning it on is the only time JUMP asks for Screen Recording.
    private func setRecognizesScreenText(_ enabled: Bool) {
        settings.setRecognizesScreenText(enabled)
        guard enabled else { return }
        if !screenRecording.isGranted {
            screenRecording.request()
        }
        if screenRecording.isGranted {
            Task { await recognizer.prefetch() }
        }
    }

    private func applyCharacters() {
        charactersRejected = !settings.setHintCharacters(characters)
        characters = settings.hintCharacters
    }
}
