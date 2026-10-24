import AppKit

/// What the overlay needs to draw one hint.
public struct HintPresentation: Sendable, Equatable {
    public let label: String
    public let anchor: HintAnchor

    public nonisolated init(label: String, anchor: HintAnchor) {
        self.label = label
        self.anchor = anchor
    }
}

/// Transparent, click-through panels (one per screen) that draw hints above everything.
public final class HintOverlay {
    private var panels: [OverlayPanel] = []

    public private(set) var isVisible = false

    public init() {}

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
            panel.hintsView.items = hints.compactMap { hint in
                let point = ScreenGeometry.appKitPoint(fromAX: hint.anchor.point, primaryScreenHeight: primaryHeight)
                guard screenFrame.contains(point) else { return nil }
                return HintsView.Item(
                    label: hint.label,
                    point: CGPoint(x: point.x - screenFrame.minX, y: point.y - screenFrame.minY),
                    alignment: hint.anchor.alignment
                )
            }
            panel.orderFrontRegardless()
        }

        let keyPanel = focus.flatMap { point in panels.first { $0.frame.contains(point) } } ?? panels.first
        keyPanel?.makeKey()
        isVisible = true
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
