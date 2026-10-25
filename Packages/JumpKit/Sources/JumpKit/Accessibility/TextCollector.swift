import ApplicationServices

/// How a jump to a text match is carried out.
public enum TextJumpPlan: Sendable, Equatable {
    /// Focus the text input and put the caret at this UTF-16 offset.
    case placeCaret(location: Int)
    /// Synthesize the hint action as pointer events at the point.
    case click(HintAction, at: CGPoint)
}

/// Reads the visible text of the focused window, off the main thread, and
/// jumps to a match.
public nonisolated enum TextCollector {
    /// Roles whose `AXValue` is text on screen.
    static let valueRoles: Set<String> = ["AXStaticText", "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// Controls whose `AXTitle` is their visible label.
    static let titleRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXLink",
        "AXMenuItem", "AXDisclosureTriangle",
    ]
    static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Most nodes a collection reads; a guard against huge trees on top of the deadline.
    static let nodeLimit = 4000

    /// The text a node shows, or `nil`. Never `AXDescription`: that is the
    /// spoken label of icons, not text on screen.
    static func visibleText(role: String, value: String?, title: String?) -> String? {
        let text: String? = switch source(role: role) {
        case .value: value
        case .title: title
        case nil: nil
        }
        // Not trimmed: match ranges are UTF-16 offsets into the full AXValue.
        guard let text, !text.allSatisfy(\.isWhitespace) else { return nil }
        return text
    }

    /// Which attribute holds the text a role shows.
    static func source(role: String) -> TextSource? {
        if valueRoles.contains(role) { .value } else if titleRoles.contains(role) { .title } else { nil }
    }

    static func isEditable(role: String) -> Bool {
        editableRoles.contains(role)
    }

    /// The run a node with a usable frame contributes, or `nil` when it shows no text.
    static func run<Node>(role: String, frame: CGRect, value: String?, title: String?, visibleRange: NSRange? = nil,
                          isCoarse: Bool = false, node: Node) -> TextRun<Node>? {
        guard let source = source(role: role), let text = visibleText(role: role, value: value, title: title)
        else { return nil }
        return TextRun(text: text, source: source, frame: frame, role: role, isEditable: isEditable(role: role),
                       visibleRange: visibleRange, isCoarse: isCoarse, node: node)
    }

    /// A text area that cannot measure words: its matches only know the whole
    /// area, so a search prefers recognized words (OCR) over them.
    static func isCoarse(role: String, supportsWordBounds: Bool) -> Bool {
        role == "AXTextArea" && !supportsWordBounds
    }

    /// Roles whose text can scroll inside the element, so only part of it is on screen.
    static func readsVisibleRange(role: String) -> Bool {
        role == "AXTextArea" || role == "AXTextField"
    }

    /// Whether `AXBoundsForRange` can measure ranges into the run's text.
    static func measuresWordBounds<Node>(_ run: TextRun<Node>) -> Bool {
        run.source == .value
    }

    static func plan<Node>(_ action: HintAction, for match: TextMatch<Node>) -> TextJumpPlan {
        if match.run.isEditable, case .press = action {
            return .placeCaret(location: match.range.location)
        }
        return .click(action, at: CGPoint(x: match.frame.midX, y: match.frame.midY))
    }

    // MARK: Live accessibility

    /// The focused window's frame in AX coordinates.
    @concurrent
    public static func windowFrame(pid: pid_t) async throws -> CGRect {
        guard let window = focusedWindow(pid: pid),
              let frame = frame(of: window)
        else { throw FocusedWindowScanError.noFocusedWindow }
        return frame
    }

    /// Visible text of the focused window: one batched read per node, nodes
    /// outside the window skipped, web areas through one search-predicate query.
    @concurrent
    public static func collect(pid: pid_t, budget: Duration = .milliseconds(250)) async throws -> [TextRun<AXNode>] {
        let deadline = ContinuousClock.now.advanced(by: budget)
        guard let window = focusedWindow(pid: pid) else { throw FocusedWindowScanError.noFocusedWindow }
        let windowFrame = frame(of: window) ?? .infinite
        var walk = Walk(windowFrame: windowFrame, deadline: deadline)
        walk.run(from: window)
        return walk.runs
    }

    /// Screen bounds of the match's characters, or `nil` when the app does not
    /// report them (only `AXValue` text supports it; Ghostty never does). Control
    /// titles are never measured: the run frame stands in for them.
    @concurrent
    public static func wordBounds(for match: TextMatch<AXNode>) async -> CGRect? {
        guard measuresWordBounds(match.run) else { return nil }
        var range = CFRange(location: match.range.location, length: match.range.length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            match.run.node.element, "AXBoundsForRange" as CFString, parameter, &bounds) == .success,
            let bounds, CFGetTypeID(bounds) == AXValueGetTypeID()
        else { return nil }
        var box = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &box), box.width > 0, box.height > 0 else { return nil }
        return box
    }

    /// Jumps to the match: the caret in text inputs, else a click on the word
    /// with the hint modifiers' click type.
    @concurrent
    public static func jump(_ action: HintAction, to match: TextMatch<AXNode>) async {
        switch plan(action, for: match) {
        case .placeCaret(let location):
            if placeCaret(in: match.run.node.element, at: location) { return }
            // The input refused focus: a click still lands in it.
            ElementActions.click(.press, at: CGPoint(x: match.frame.midX, y: match.frame.midY))
        case .click(let action, let point):
            ElementActions.click(action, at: point)
        }
    }

    private static func placeCaret(in element: AXUIElement, at location: Int) -> Bool {
        guard AXUIElementSetAttributeValue(element, "AXFocused" as CFString, kCFBooleanTrue) == .success else { return false }
        var range = CFRange(location: location, length: 0)
        guard let value = AXValueCreate(.cfRange, &range) else { return true }
        // Focus alone already helps; some fields ignore the selection write.
        AXUIElementSetAttributeValue(element, "AXSelectedTextRange" as CFString, value)
        return true
    }

    /// Whether the element measures its text: one `AXBoundsForRange` call on
    /// its first character.
    private static func supportsWordBounds(_ element: AXUIElement) -> Bool {
        var range = CFRange(location: 0, length: 1)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return false }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, "AXBoundsForRange" as CFString, parameter, &bounds) == .success,
            let bounds, CFGetTypeID(bounds) == AXValueGetTypeID()
        else { return false }
        var box = CGRect.zero
        return AXValueGetValue(bounds as! AXValue, .cgRect, &box) && box.width > 0 && box.height > 0
    }

    /// `AXVisibleCharacterRange`, or `nil` when the element does not report it.
    private static func visibleCharacterRange(of element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXVisibleCharacterRange" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0
        else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXNode.messagingTimeout)
        // Reading any attribute wakes Chromium's lazily built accessibility tree (Vimac trick).
        let _: String? = AXNode.copyAttribute("AXRole", of: app)
        guard let window: AXUIElement = AXNode.copyAttribute("AXFocusedWindow", of: app) else { return nil }
        AXUIElementSetMessagingTimeout(window, AXNode.messagingTimeout)
        return window
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, ["AXPosition", "AXSize"] as CFArray, [], &values) == .success,
              let values = values as? [AnyObject], values.count == 2
        else { return nil }
        return rect(values[0], values[1])
    }

    // Missing attributes come back as an AXValue of error type; AXValueGetValue
    // returns false for any type mismatch, so this also rejects those.
    static func rect(_ position: AnyObject, _ size: AnyObject) -> CGRect? {
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// One depth-first traversal of the window.
    private struct Walk {
        let windowFrame: CGRect
        let deadline: ContinuousClock.Instant
        var runs: [TextRun<AXNode>] = []
        var visited = 0

        private static let names = ["AXRole", "AXPosition", "AXSize", "AXChildren", "AXValue", "AXTitle"]
        private static let hitNames = ["AXRole", "AXPosition", "AXSize", "AXValue", "AXTitle"]

        var isOutOfBudget: Bool { visited >= TextCollector.nodeLimit || ContinuousClock.now > deadline }

        mutating func run(from window: AXUIElement) {
            var stack = [window]
            while let element = stack.popLast(), !isOutOfBudget {
                AXUIElementSetMessagingTimeout(element, AXNode.messagingTimeout)
                var values: CFArray?
                guard AXUIElementCopyMultipleAttributeValues(element, Self.names as CFArray, [], &values) == .success,
                      let values = values as? [AnyObject], values.count == 6,
                      let role = values[0] as? String
                else { continue }
                visited += 1
                let frame = TextCollector.rect(values[1], values[2])
                // Off-window content (scrolled away, other tabs) is not on screen.
                if let frame, !frame.intersects(windowFrame), element != window { continue }
                if role == "AXWebArea", addWebText(of: element) { continue }
                add(element, role: role, frame: frame, value: values[4] as? String, title: values[5] as? String)
                let children: [AXUIElement] = if role == "AXTable" || role == "AXOutline" {
                    // Tables and outlines can hold thousands of rows; only visible ones matter.
                    AXNode.copyAttribute("AXVisibleRows", of: element) ?? []
                } else {
                    values[3] as? [AXUIElement] ?? []
                }
                stack.append(contentsOf: children.reversed())
            }
        }

        private mutating func add(_ element: AXUIElement, role: String, frame: CGRect?, value: String?, title: String?) {
            guard let frame, frame.width > 0, frame.height > 0, frame.intersects(windowFrame),
                  TextCollector.visibleText(role: role, value: value, title: title) != nil
            else { return }
            // Large text areas scroll: only the part on screen should match.
            let visibleRange = TextCollector.readsVisibleRange(role: role)
                ? TextCollector.visibleCharacterRange(of: element) : nil
            let isCoarse = role == "AXTextArea"
                && TextCollector.isCoarse(role: role, supportsWordBounds: TextCollector.supportsWordBounds(element))
            guard let run = TextCollector.run(role: role, frame: frame, value: value, title: title,
                                              visibleRange: visibleRange, isCoarse: isCoarse, node: AXNode(element))
            else { return }
            runs.append(run)
        }

        /// Visible text and text fields of a web area through the search
        /// predicate (15 ms against 160 ms for walking it). Returns `false`
        /// when the engine rejects the query, so the area is walked instead.
        private mutating func addWebText(of webArea: AXUIElement) -> Bool {
            var hits = search(webArea, keys: ["AXStaticTextSearchKey", "AXTextFieldSearchKey"])
            if hits?.isEmpty ?? true {
                // Older Chromium only honors a single search key per query.
                hits = search(webArea, keys: "AXStaticTextSearchKey")
            }
            guard let hits else { return false }
            for hit in hits {
                guard !isOutOfBudget else { break }
                AXUIElementSetMessagingTimeout(hit, AXNode.messagingTimeout)
                var values: CFArray?
                guard AXUIElementCopyMultipleAttributeValues(hit, Self.hitNames as CFArray, [], &values) == .success,
                      let values = values as? [AnyObject], values.count == 5,
                      let role = values[0] as? String
                else { continue }
                visited += 1
                add(hit, role: role, frame: TextCollector.rect(values[1], values[2]),
                    value: values[3] as? String, title: values[4] as? String)
            }
            return true
        }

        private func search(_ webArea: AXUIElement, keys: Any) -> [AXUIElement]? {
            let query: [String: Any] = [
                "AXDirection": "AXDirectionNext",
                "AXImmediateDescendantsOnly": false,
                "AXResultsLimit": -1,
                "AXVisibleOnly": true,
                "AXSearchKey": keys,
            ]
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                webArea, "AXUIElementsForSearchPredicate" as CFString, query as CFDictionary, &value) == .success
            else { return nil }
            return value as? [AXUIElement] ?? []
        }
    }
}
