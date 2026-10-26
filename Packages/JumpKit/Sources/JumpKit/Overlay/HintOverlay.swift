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

    /// Whether one of the overlay panels currently receives the keyboard.
    public var hasKeyPanel: Bool {
        panels.contains { $0.isKeyWindow }
    }

    public func isOverlayWindow(_ object: Any?) -> Bool {
        guard let window = object as? NSWindow else { return false }
        return panels.contains { $0 === window }
    }

    /// Read on every `show`, so appearance changes apply to the next hints.
    private let hintAppearance: () -> HintAppearance
    private let showsScrollOutline: () -> Bool

    public init(hintAppearance: @escaping () -> HintAppearance = { .standard },
                showsScrollOutline: @escaping () -> Bool = { true }) {
        self.hintAppearance = hintAppearance
        self.showsScrollOutline = showsScrollOutline
    }

    /// Creates the panels and warms up text rendering ahead of the first
    /// hotkey press, which otherwise pays ~45 ms for it. Call at launch and
    /// whenever the display arrangement changes.
    public func prepare() {
        // Rebuilding panels now would remove visible hints while input still
        // goes to hint mode; `show` resyncs them next time anyway.
        guard !isVisible else { return }
        syncPanels(with: NSScreen.screens)
        HintsView.warmUpTextRendering(hintAppearance())
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

        let appearance = hintAppearance()
        for panel in panels {
            let screenFrame = panel.frame
            panel.hintsView.hintAppearance = appearance
            panel.hintsView.typed = ""
            panel.hintsView.outline = nil
            panel.hintsView.search = nil
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
            // Liquid Glass pills are subviews, placed by layout.
            panel.hintsView.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
        }

        let keyPanel = focus.flatMap { point in panels.first { $0.frame.contains(point) } } ?? panels.first
        keyPanel?.makeKey()
        isVisible = true
    }

    /// The outline of `area` in a panel's coordinates, or `nil` when hidden or
    /// on another screen. A hidden outline still lets the panel take the keyboard.
    static func outline(_ area: CGRect, in panelFrame: CGRect, shown: Bool) -> CGRect? {
        guard shown, panelFrame.intersects(area) else { return nil }
        return area.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
    }

    /// Outlines one area (AX coordinates) for scroll mode and makes its panel
    /// key, so keystrokes reach JUMP without activating it. Returns whether the
    /// panel became key; without it no key would reach scroll mode.
    @discardableResult
    public func showOutline(_ frame: CGRect) -> Bool {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return false }
        syncPanels(with: screens)
        let appKitFrame = ScreenGeometry.appKitRect(fromAX: frame, primaryScreenHeight: primary.frame.height)

        let shown = showsScrollOutline()
        for panel in panels {
            panel.hintsView.items = []
            panel.hintsView.search = nil
            panel.hintsView.outline = Self.outline(appKitFrame, in: panel.frame, shown: shown)
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
        }
        let center = CGPoint(x: appKitFrame.midX, y: appKitFrame.midY)
        let keyPanel = panels.first { $0.frame.contains(center) } ?? panels.first
        keyPanel?.makeKey()
        isVisible = true
        return keyPanel?.isKeyWindow ?? false
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
            panel.hintsView.outline = nil
            panel.hintsView.search = nil
            panel.orderOut(nil)
        }
        isVisible = false
    }

    private func syncPanels(with screens: [NSScreen]) {
        syncPanels(withFrames: screens.map(\.frame))
    }

    /// Rebuilds the panels only when the display arrangement changed.
    func syncPanels(withFrames frames: [CGRect]) {
        guard panels.map(\.frame) != frames else { return }
        panels.forEach { $0.close() }
        panels = frames.map(OverlayPanel.init)
    }

    /// One view per screen, in screen order.
    var panelViews: [HintsView] {
        panels.map(\.hintsView)
    }
}

extension HintOverlay: SearchOverlayPresenting {
    /// Shows the search box over the window's top center and every match in
    /// the hint theme. The first call makes the box's panel key, so keystrokes
    /// reach JUMP without activating it; returns whether a panel is key.
    @discardableResult
    public func showSearch(_ presentation: SearchPresentation) -> Bool {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return false }
        syncPanels(with: screens)
        let boxPanel = applySearch(presentation, primaryScreenHeight: primary.frame.height)

        for panel in panels {
            panel.orderFrontRegardless()
            // Draw now, as `show` does, so the box is on screen when this returns.
            panel.hintsView.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
        }

        guard !isVisible else { return hasKeyPanel }
        let keyPanel = boxPanel.map { panels[$0] } ?? panels.first
        keyPanel?.makeKey()
        isVisible = true
        return keyPanel?.isKeyWindow ?? false
    }

    /// Gives each panel its part of the search, replacing hints and outline.
    /// Returns the index of the panel holding the search box.
    @discardableResult
    func applySearch(_ presentation: SearchPresentation, primaryScreenHeight: CGFloat) -> Int? {
        let boxPanel = SearchLayout.boxPanelIndex(for: presentation.windowFrame, panelFrames: panels.map(\.frame),
                                                  primaryScreenHeight: primaryScreenHeight)
        let appearance = hintAppearance()
        for (index, panel) in panels.enumerated() {
            let view = panel.hintsView
            view.hintAppearance = appearance
            view.items = []
            view.typed = ""
            view.outline = nil
            view.search = SearchLayout.search(for: presentation, panelFrame: panel.frame,
                                              primaryScreenHeight: primaryScreenHeight, showsBox: index == boxPanel)
        }
        return boxPanel
    }
}

/// Borderless panel covering one screen. It can become key (to receive typed
/// labels) without activating JUMP, and never intercepts the mouse.
private final class OverlayPanel: NSPanel {
    let hintsView: HintsView

    init(frame: CGRect) {
        hintsView = HintsView(frame: CGRect(origin: .zero, size: frame.size))
        super.init(
            contentRect: frame,
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
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}
