import AppKit

/// What the overlay needs to draw one hint.
public struct HintPresentation: Sendable, Equatable {
    public let label: String
    public let anchor: HintAnchor
    /// Element frame in AX coordinates.
    public let elementFrame: CGRect

    public nonisolated init(label: String, anchor: HintAnchor, elementFrame: CGRect) {
        self.label = label
        self.anchor = anchor
        self.elementFrame = elementFrame
    }
}

/// Transparent, click-through panels (one per screen) that draw hints above everything.
public final class HintOverlay {
    private var panels: [OverlayPanel] = []

    public private(set) var isVisible = false

    public init() {}

    /// Creates the panels and warms up text rendering ahead of the first
    /// hotkey press, which otherwise pays ~45 ms for it. Call at launch and
    /// whenever the display arrangement changes.
    public func prepare() {
        // Rebuilding panels now would remove visible hints while input still
        // goes to hint mode; `show` resyncs them next time anyway.
        guard !isVisible else { return }
        syncPanels(with: NSScreen.screens)
        HintsView.warmUpTextRendering()
        // The window server allocates a panel's backing store the first time it
        // is shown. Showing the empty, transparent, click-through panels once
        // now moves that cost out of the first hotkey press.
        for panel in panels {
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
            panel.orderOut(nil)
        }
    }

    /// Shows `hints` and makes the panel under `focusPoint` (AX coordinates) key,
    /// so keystrokes reach JUMP without activating it.
    public func show(_ hints: [HintPresentation], focusPoint: CGPoint?) {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        syncPanels(with: screens)

        let primaryHeight = primary.frame.height
        let focus = focusPoint.map { ScreenGeometry.appKitPoint(fromAX: $0, primaryScreenHeight: primaryHeight) }

        for panel in panels {
            let screenFrame = panel.frame
            panel.hintsView.typed = ""
            panel.hintsView.items = hints.compactMap { hint in
                let point = ScreenGeometry.appKitPoint(fromAX: hint.anchor.point, primaryScreenHeight: primaryHeight)
                guard screenFrame.contains(point) else { return nil }
                let frame = ScreenGeometry.appKitRect(fromAX: hint.elementFrame, primaryScreenHeight: primaryHeight)
                let origin = screenFrame.origin
                return HintsView.Item(
                    label: hint.label,
                    anchor: HintAnchor(point: CGPoint(x: point.x - origin.x, y: point.y - origin.y), alignment: hint.anchor.alignment),
                    elementFrame: frame.offsetBy(dx: -origin.x, dy: -origin.y)
                )
            }
            panel.orderFrontRegardless()
            // Draw now rather than on the next display cycle, so the hints are
            // on screen when `show` returns (and latency measurements are honest).
            panel.displayIfNeeded()
        }

        let keyPanel = focus.flatMap { point in panels.first { $0.frame.contains(point) } } ?? panels.first
        keyPanel?.makeKey()
        isVisible = true
    }

    /// Keeps only hints starting with `typed`, with those characters dimmed.
    public func filter(typed: String) {
        panels.forEach { $0.hintsView.typed = typed }
    }

    /// Swaps which of the overlapping hints is on top.
    public func rotate() {
        panels.forEach { $0.hintsView.rotate() }
    }

    public func hide() {
        for panel in panels {
            panel.hintsView.items = []
            panel.orderOut(nil)
        }
        isVisible = false
    }

    /// Rebuilds the panels only when the display arrangement changed.
    private func syncPanels(with screens: [NSScreen]) {
        guard panels.map(\.frame) != screens.map(\.frame) else { return }
        panels.forEach { $0.close() }
        panels = screens.map(OverlayPanel.init)
    }
}

/// Borderless panel covering one screen. It can become key (to receive typed
/// labels) without activating JUMP, and never intercepts the mouse.
private final class OverlayPanel: NSPanel {
    let hintsView: HintsView

    init(screen: NSScreen) {
        hintsView = HintsView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        contentView = hintsView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}
