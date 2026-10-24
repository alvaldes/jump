import CoreGraphics
import Testing
@testable import JumpKit

@Suite("ElementActions")
struct ElementActionsTests {
    @Test func clicksTheCenterOfMostElements() {
        let point = ElementActions.clickPoint(role: "AXButton", frame: CGRect(x: 100, y: 50, width: 40, height: 20))
        #expect(point == CGPoint(x: 120, y: 60))
    }

    @Test func clicksLinksNearTheirBottomLeftWhereTheHintIs() {
        // Multi-line links have empty space at their center.
        let point = ElementActions.clickPoint(role: "AXLink", frame: CGRect(x: 100, y: 50, width: 300, height: 40))
        #expect(point == CGPoint(x: 105, y: 85))
    }

    @Test func clicksInsideTinyLinks() {
        let point = ElementActions.clickPoint(role: "AXLink", frame: CGRect(x: 100, y: 50, width: 6, height: 4))
        #expect(point == CGPoint(x: 103, y: 52))
    }
}
