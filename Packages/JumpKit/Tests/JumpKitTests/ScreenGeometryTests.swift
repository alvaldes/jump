import CoreGraphics
import Testing
@testable import JumpKit

@Suite("ScreenGeometry")
struct ScreenGeometryTests {
    /// Primary display 1440x900: AX origin is its top-left, AppKit origin its bottom-left.
    private let primaryHeight: CGFloat = 900

    @Test func flipsARectOnThePrimaryScreen() {
        let ax = CGRect(x: 100, y: 50, width: 200, height: 30)
        let appKit = ScreenGeometry.appKitRect(fromAX: ax, primaryScreenHeight: primaryHeight)
        #expect(appKit == CGRect(x: 100, y: 820, width: 200, height: 30))
    }

    @Test func handlesAScreenAboveThePrimary() {
        // A display stacked above the primary has negative AX y values.
        let ax = CGRect(x: 0, y: -500, width: 100, height: 100)
        let appKit = ScreenGeometry.appKitRect(fromAX: ax, primaryScreenHeight: primaryHeight)
        #expect(appKit == CGRect(x: 0, y: 1300, width: 100, height: 100))
    }

    @Test func handlesAScreenBelowThePrimary() {
        let ax = CGRect(x: 0, y: 1000, width: 100, height: 100)
        let appKit = ScreenGeometry.appKitRect(fromAX: ax, primaryScreenHeight: primaryHeight)
        #expect(appKit == CGRect(x: 0, y: -200, width: 100, height: 100))
    }

    @Test func flipsAPoint() {
        let point = ScreenGeometry.appKitPoint(fromAX: CGPoint(x: 100, y: 50), primaryScreenHeight: primaryHeight)
        #expect(point == CGPoint(x: 100, y: 850))
    }

    @Test func conversionIsReversible() {
        let ax = CGRect(x: -300, y: 120, width: 40, height: 60)
        let appKit = ScreenGeometry.appKitRect(fromAX: ax, primaryScreenHeight: primaryHeight)
        #expect(ScreenGeometry.axRect(fromAppKit: appKit, primaryScreenHeight: primaryHeight) == ax)
    }
}
