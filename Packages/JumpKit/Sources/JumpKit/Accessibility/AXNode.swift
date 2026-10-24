import ApplicationServices

/// Live `AccessibilityNode` backed by an `AXUIElement`.
///
/// Attribute names are spelled out as strings: the imported `kAX…` globals
/// are not concurrency-safe under Swift 6.
public nonisolated struct AXNode: AccessibilityNode, @unchecked Sendable {
    // AXUIElement is an immutable CF handle; the AX API is safe to call from any thread.
    public let element: AXUIElement

    /// Children delivered with the frame in the same round-trip, so traversal
    /// costs one IPC per node instead of two.
    private let prefetched = PrefetchedChildren()

    /// Upper bound for a single AX request, so a hung app cannot stall a scan
    /// (Vimac used 1 s globally).
    static let messagingTimeout: Float = 0.25

    /// Whether `attributes()` also fetches the children. Off for children of
    /// scroll areas: those are often tables, whose full row list can be
    /// thousands of elements when only the visible rows are needed.
    private let prefetchesChildren: Bool

    public init(_ element: AXUIElement) {
        self.init(element, prefetchesChildren: true)
    }

    private init(_ element: AXUIElement, prefetchesChildren: Bool) {
        self.element = element
        self.prefetchesChildren = prefetchesChildren
        // The timeout applies only to this exact reference, never to the
        // children copied from it, so every node sets its own. Local call, no IPC.
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
    }

    private static let frameAttributes = ["AXRole", "AXPosition", "AXSize"]
    private static let batchedAttributes = frameAttributes + ["AXChildren"]

    public func attributes(prefetchingChildren: Bool) -> NodeAttributes? {
        // One IPC round-trip for role, position, size and children.
        let prefetch = prefetchingChildren && prefetchesChildren
        let names = prefetch ? Self.batchedAttributes : Self.frameAttributes
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values) == .success,
              let values = values as? [AnyObject], values.count == names.count,
              let role = values[0] as? String,
              let origin = Self.point(values[1]),
              let size = Self.size(values[2])
        else { return nil }
        if prefetch {
            prefetched.elements = values[3] as? [AXUIElement] ?? []
        }
        return NodeAttributes(role: role, frame: CGRect(origin: origin, size: size))
    }

    public func actions() -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    public func children(role: String) -> [AXNode] {
        // Tables and outlines can hold thousands of rows; only visible ones matter.
        if role == "AXTable" || role == "AXOutline" {
            let rows: [AXUIElement]? = Self.copyAttribute("AXVisibleRows", of: element)
            return rows?.map(AXNode.init) ?? []
        }
        let elements = prefetched.elements ?? Self.copyAttribute("AXChildren", of: element) ?? []
        let prefetch = role != "AXScrollArea"
        return elements.map { AXNode($0, prefetchesChildren: prefetch) }
    }

    /// Search keys from Vimac: everything a user may want to click or type into.
    private static let webSearchKeys = [
        "AXButtonSearchKey", "AXCheckBoxSearchKey", "AXControlSearchKey", "AXGraphicSearchKey",
        "AXLinkSearchKey", "AXRadioGroupSearchKey", "AXTextFieldSearchKey",
    ]

    public func webTargets() -> [AXNode]? {
        let query: [String: Any] = [
            "AXDirection": "AXDirectionNext",
            "AXImmediateDescendantsOnly": false,
            "AXResultsLimit": -1,
            "AXVisibleOnly": true,
        ]
        func search(_ keys: Any) -> (supported: Bool, elements: [AXUIElement]) {
            var parameters = query
            parameters["AXSearchKey"] = keys
            var value: CFTypeRef?
            let error = AXUIElementCopyParameterizedAttributeValue(
                element, "AXUIElementsForSearchPredicate" as CFString, parameters as CFDictionary, &value
            )
            return (error == .success, value as? [AXUIElement] ?? [])
        }

        let combined = search(Self.webSearchKeys)
        guard combined.supported else { return nil }
        var elements = combined.elements
        if elements.isEmpty {
            // Older Chromium only honors a single search key per query.
            var seen = Set<AXUIElement>()
            elements = Self.webSearchKeys.flatMap { search($0).elements }.filter { seen.insert($0).inserted }
        }
        return elements.map { AXNode($0, prefetchesChildren: false) }
    }

    static func copyAttribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    // Missing attributes come back as an AXValue of error type; AXValueGetValue
    // returns false for any type mismatch, so these also reject those.
    private static func point(_ object: AnyObject) -> CGPoint? {
        guard CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(object as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(_ object: AnyObject) -> CGSize? {
        guard CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(object as! AXValue, .cgSize, &size) ? size : nil
    }
}

/// Written once by `attributes()` and read by `children(role:)` on the same
/// scan task, so it needs no locking.
private nonisolated final class PrefetchedChildren: @unchecked Sendable {
    nonisolated(unsafe) var elements: [AXUIElement]?
}
