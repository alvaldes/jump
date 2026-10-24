import ApplicationServices

/// Live `AccessibilityNode` backed by an `AXUIElement`.
///
/// Attribute names are spelled out as strings: the imported `kAX…` globals
/// are not concurrency-safe under Swift 6.
public nonisolated struct AXNode: AccessibilityNode, @unchecked Sendable {
    // AXUIElement is an immutable CF handle; the AX API is safe to call from any thread.
    public let element: AXUIElement

    /// Upper bound for a single AX request, so a hung app cannot stall a scan
    /// (Vimac used 1 s globally).
    static let messagingTimeout: Float = 0.25

    public init(_ element: AXUIElement) {
        self.element = element
        // The timeout applies only to this exact reference, never to the
        // children copied from it, so every node sets its own. Local call, no IPC.
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
    }

    private static let frameAttributes = ["AXRole", "AXPosition", "AXSize"]

    public func attributes() -> NodeAttributes? {
        // One IPC round-trip for role, position and size.
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, Self.frameAttributes as CFArray, [], &values) == .success,
              let values = values as? [AnyObject], values.count == 3,
              let role = values[0] as? String,
              let origin = Self.point(values[1]),
              let size = Self.size(values[2])
        else { return nil }

        var actionNames: CFArray?
        let actions = AXUIElementCopyActionNames(element, &actionNames) == .success
            ? (actionNames as? [String] ?? [])
            : []

        return NodeAttributes(role: role, frame: CGRect(origin: origin, size: size), actions: actions)
    }

    public func children(role: String) -> [AXNode] {
        // Tables and outlines can hold thousands of rows; only visible ones matter.
        let attribute = (role == "AXTable" || role == "AXOutline") ? "AXVisibleRows" : "AXChildren"
        let elements: [AXUIElement]? = Self.copyAttribute(attribute, of: element)
        return elements?.map(AXNode.init) ?? []
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
