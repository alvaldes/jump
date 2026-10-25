import JumpKit
import SwiftUI

struct BehaviorSettings: View {
    let settings: JumpSettings
    let screenRecording: ScreenRecordingPermission
    let recognizer: ScreenTextRecognizer

    @State private var characters = ""
    @State private var charactersRejected = false

    var body: some View {
        SettingsPane {
            Section("Hints") {
                LabeledContent("Hint characters:") {
                    TextField("Hint characters", text: $characters)
                        .labelsHidden()
                        .font(.body.monospaced())
                        .multilineTextAlignment(.trailing)
                        .onSubmit(applyCharacters)
                }
                if charactersRejected {
                    Text("Use at least two different letters.")
                        .foregroundStyle(.red)
                } else {
                    Text("Labels are built from these letters, first ones first. Press Return to apply.")
                        .foregroundStyle(.secondary)
                }
                Button("Restore Default") {
                    characters = HintLabels.defaultCharacters
                    applyCharacters()
                }
            }

            Section("Text Search") {
                Toggle("Recognize text on screen (OCR)", isOn: Binding(
                    get: { settings.recognizesScreenText },
                    set: { setRecognizesScreenText($0) }
                ))
                Text("When a window has no readable text, such as terminals, PDFs and images, text search reads it from the screen. Needs Screen Recording access.")
                    .foregroundStyle(.secondary)
                if settings.recognizesScreenText, !screenRecording.isGranted {
                    Text("Allow JUMP in Screen & System Audio Recording to search text on screen; until then text search uses Accessibility only. JUMP may need to be reopened after allowing it.")
                        .foregroundStyle(.orange)
                    Button("Open Privacy Settings") {
                        screenRecording.openPrivacySettings()
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
