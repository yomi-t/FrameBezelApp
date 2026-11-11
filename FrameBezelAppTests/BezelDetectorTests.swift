import Testing
import CoreGraphics
@testable import FrameBezelApp

struct BezelDetectorTests {
    @Test func detectsRectangularWindowExactly() throws {
        let image = TestSupport.bezelImage(width: 100, height: 200, screen: CGRect(x: 20, y: 30, width: 60, height: 140))
        let a = try BezelDetector.detect(image: image)
        #expect(a.x == 20 && a.y == 30)
        #expect(a.width == 60 && a.height == 140)
        #expect(a.cornerRadius == 0)
    }

    @Test func originIsTopLeftNotBottomLeft() throws {
        // 窓が上寄り（y=5）にあるとき、検出された y も 5 になる（CG の下原点で数えない）
        let image = TestSupport.bezelImage(width: 100, height: 200, screen: CGRect(x: 10, y: 5, width: 80, height: 50))
        let a = try BezelDetector.detect(image: image)
        #expect(a.y == 5 && a.height == 50)
    }

    @Test func ignoresTransparentOuterCorners() throws {
        // 枠の外側（四隅）が透明でも、画面領域には含めない
        let image = TestSupport.bezelImage(width: 100, height: 200, screen: CGRect(x: 20, y: 20, width: 60, height: 160),
                                           outerCornerClear: true)
        let a = try BezelDetector.detect(image: image)
        #expect(a.x == 20 && a.y == 20 && a.width == 60 && a.height == 160)
    }

    @Test func estimatesCornerRadiusOfRoundedWindow() throws {
        let image = TestSupport.roundedBezelImage(width: 200, height: 400, screen: CGRect(x: 20, y: 20, width: 160, height: 360), radius: 30)
        let a = try BezelDetector.detect(image: image)
        #expect(a.width == 160 && a.height == 360)
        #expect(abs(a.cornerRadius - 30) <= 4)
    }

    @Test func radiusNeverExceedsHalfOfShortSide() throws {
        let image = TestSupport.roundedBezelImage(width: 100, height: 100, screen: CGRect(x: 10, y: 10, width: 80, height: 80), radius: 40)
        let a = try BezelDetector.detect(image: image)
        #expect(a.cornerRadius <= 40)
    }

    @Test func throwsWhenThereIsNoWindow() {
        let opaque = TestSupport.solid(50, 50)
        #expect(throws: BezelDetectorError.self) { try BezelDetector.detect(image: opaque) }
    }

    @Test func throwsWhenOnlyTheOutsideIsTransparent() {
        // 全面透明は「縁から連結した外側」なので画面領域ではない
        let clear = TestSupport.bezelImage(width: 50, height: 50, screen: CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(throws: BezelDetectorError.self) { try BezelDetector.detect(image: clear) }
    }

    @Test func throwsForTinyImages() {
        #expect(throws: BezelDetectorError.self) { try BezelDetector.detect(image: TestSupport.solid(2, 2)) }
    }

    @Test func largestWindowWinsAsBoundingBoxOfAllInnerTransparency() throws {
        // 窓が 2 つに分かれていても外接矩形になる
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: TestSupport.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        ctx.clear(CGRect(x: 10, y: 10, width: 20, height: 20))
        ctx.clear(CGRect(x: 60, y: 60, width: 20, height: 20))
        let a = try BezelDetector.detect(image: ctx.makeImage()!)
        #expect(a.x == 10 && a.width == 70)
        #expect(a.y == 20 && a.height == 70)
    }
}
