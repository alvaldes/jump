import CoreGraphics

/// Text recognized on screen (OCR), the fallback source of text search: its
/// matches are used for a query only when Accessibility has none.
public struct ScreenTextSource {
    /// Recognized lines of the app's window at the frame (AX coordinates).
    public typealias Recognizer = (FrontmostApp, CGRect) async throws -> [TextRun<ScreenText>]
    public typealias Performer = (HintAction, TextMatch<ScreenText>) async -> Void

    /// Read when the mode opens: the setting is on and Screen Recording is granted.
    public var isEnabled: () -> Bool
    public var recognize: Recognizer
    /// Jumps to a recognized match (a click at its center, never a caret).
    public var perform: Performer

    public init(isEnabled: @escaping () -> Bool, recognize: @escaping Recognizer, perform: @escaping Performer) {
        self.isEnabled = isEnabled
        self.recognize = recognize
        self.perform = perform
    }
}
