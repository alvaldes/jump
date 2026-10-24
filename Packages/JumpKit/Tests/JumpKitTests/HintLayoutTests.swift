import CoreGraphics
import Testing
@testable import JumpKit

@Suite("HintLayout")
struct HintLayoutTests {
    private let pill = CGSize(width: 24, height: 16)

    private func request(at point: CGPoint, element: CGRect) -> HintLayout.Request {
        HintLayout.Request(size: pill, anchor: HintAnchor(point: point, alignment: .center), elementFrame: element)
    }

    @Test func separateHintsKeepTheirPreferredPlace() {
        let rects = HintLayout.place([
            request(at: CGPoint(x: 50, y: 50), element: CGRect(x: 0, y: 40, width: 100, height: 20)),
            request(at: CGPoint(x: 50, y: 150), element: CGRect(x: 0, y: 140, width: 100, height: 20)),
        ])
        #expect(rects == [
            CGRect(x: 38, y: 42, width: 24, height: 16),
            CGRect(x: 38, y: 142, width: 24, height: 16),
        ])
    }

    @Test func anOverlappingHintMovesBesideTheOneAlreadyPlaced() {
        // Like a Finder row: a small icon and a wide name field side by side.
        let rects = HintLayout.place([
            request(at: CGPoint(x: 20, y: 50), element: CGRect(x: 10, y: 40, width: 20, height: 20)),
            request(at: CGPoint(x: 30, y: 50), element: CGRect(x: 30, y: 40, width: 200, height: 20)),
        ])
        #expect(!rects[0].intersects(rects[1]))
        #expect(rects[1].minY == rects[0].minY)
        #expect(rects[1].minX >= rects[0].maxX)
        #expect(rects[1].minX <= 230, "stays over its own element")
    }

    @Test func overlapIsKeptWhenThereIsNoRoomInsideTheElement() {
        let element = CGRect(x: 10, y: 40, width: 20, height: 20)
        let rects = HintLayout.place([
            request(at: CGPoint(x: 20, y: 50), element: element),
            request(at: CGPoint(x: 20, y: 50), element: element),
        ])
        #expect(rects[0] == rects[1])
    }

    @Test func bottomLeadingHintsStartAtTheirAnchor() {
        let rects = HintLayout.place([
            HintLayout.Request(
                size: pill,
                anchor: HintAnchor(point: CGPoint(x: 5, y: 7), alignment: .bottomLeading),
                elementFrame: CGRect(x: 5, y: 7, width: 80, height: 14)
            ),
        ])
        #expect(rects == [CGRect(x: 5, y: 7, width: 24, height: 16)])
    }
}
