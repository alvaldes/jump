/// Routes the hotkeys so hint, scroll and text search mode never run
/// together: they share the overlay and the keyboard.
public final class ModeSwitcher<Node: AccessibilityNode, Driver: ScrollDriving> {
    public let hints: HintMode<Node>
    public let scroll: ScrollMode<Driver>
    public let search: TextSearchMode<Node>?

    public init(hints: HintMode<Node>, scroll: ScrollMode<Driver>, search: TextSearchMode<Node>? = nil) {
        self.hints = hints
        self.scroll = scroll
        self.search = search
    }

    public func activateHints() {
        scroll.deactivate()
        search?.dismiss()
        hints.toggle()
    }

    public func activateScroll() {
        hints.dismiss()
        search?.dismiss()
        scroll.toggle()
    }

    public func activateSearch() {
        hints.dismiss()
        scroll.deactivate()
        search?.toggle()
    }
}
