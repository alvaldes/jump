import AppKit
import JumpKit

/// Screen Recording access, which recognizing text on screen (OCR) needs.
/// Only requested when the user turns that setting on.
@Observable
final class ScreenRecordingPermission {
    private(set) var isGranted = ScreenTextRecognizer.hasScreenRecordingAccess

    /// Shows the system prompt the first time; later the user must allow JUMP
    /// in System Settings.
    func request() {
        isGranted = CGRequestScreenCaptureAccess()
    }

    func refresh() {
        isGranted = ScreenTextRecognizer.hasScreenRecordingAccess
    }

    /// System Settings › Privacy & Security › Screen & System Audio Recording.
    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
