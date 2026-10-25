/// Routes the two hotkeys so hint mode and scroll mode never run together:
/// they share the overlay and the keyboard.
public final class ModeSwitcher<Node: AccessibilityNode, Driver: ScrollDriving> {
    public let hints: HintMode<Node>
    public let scroll: ScrollMode<Driver>

    public init(hints: HintMode<Node>, scroll: ScrollMode<Driver>) {
        self.hints = hints
        self.scroll = scroll
    }

    public func activateHints() {
        scroll.deactivate()
        hints.toggle()
    }

    public func activateScroll() {
        hints.dismiss()
        scroll.toggle()
    }
}
