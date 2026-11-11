import Testing
import CoreGraphics
@testable import FrameBezelApp

struct RotationTests {
    @Test func normalizesQuarterTurns() {
        #expect(Rotation(quarterTurns: 4).quarterTurns == 0)
        #expect(Rotation(quarterTurns: 5).quarterTurns == 1)
        #expect(Rotation(quarterTurns: -1).quarterTurns == 3)
        #expect(Rotation(quarterTurns: -5).quarterTurns == 3)
    }

    @Test func identityAndAxisSwap() {
        #expect(Rotation.none.isIdentity)
        #expect(!Rotation(quarterTurns: 1).isIdentity)
        #expect(Rotation(quarterTurns: 1).swapsAxes)
        #expect(!Rotation(quarterTurns: 2).swapsAxes)
        #expect(Rotation(quarterTurns: 3).swapsAxes)
    }

    @Test func rotatingCompletesAFullCircle() {
        var r = Rotation.none
        for _ in 0..<4 { r = r.rotatedClockwise() }
        #expect(r == .none)
        #expect(Rotation.none.rotatedCounterClockwise().quarterTurns == 3)
        #expect(Rotation(quarterTurns: 1).rotatedCounterClockwise() == .none)
    }
}

struct ImageRotationTests {
    // 40x20 の 4 象限画像（左上=赤 右上=緑 左下=青 右下=黄）
    private let src = TestSupport.quadrants(40, 20)
    private let red = TestSupport.RGBA(r: 255, g: 0, b: 0, a: 255)
    private let green = TestSupport.RGBA(r: 0, g: 255, b: 0, a: 255)
    private let blue = TestSupport.RGBA(r: 0, g: 0, b: 255, a: 255)
    private let yellow = TestSupport.RGBA(r: 255, g: 255, b: 0, a: 255)

    /// 四隅の少し内側の色を (左上, 右上, 左下, 右下) で返す。
    private func corners(_ image: CGImage) -> [TestSupport.RGBA] {
        let w = image.width, h = image.height
        return [TestSupport.pixel(image, 3, 3), TestSupport.pixel(image, w - 4, 3),
                TestSupport.pixel(image, 3, h - 4), TestSupport.pixel(image, w - 4, h - 4)]
    }

    @Test func identityReturnsSameImage() throws {
        let out = try #require(ImageRotation.rotate(src, .none))
        #expect(out === src)
    }

    @Test func clockwiseQuarterSwapsSizeAndMovesCorners() throws {
        let out = try #require(ImageRotation.rotate(src, Rotation(quarterTurns: 1)))
        #expect(out.width == 20 && out.height == 40)
        #expect(corners(out) == [blue, red, yellow, green])
    }

    @Test func halfTurnKeepsSize() throws {
        let out = try #require(ImageRotation.rotate(src, Rotation(quarterTurns: 2)))
        #expect(out.width == 40 && out.height == 20)
        #expect(corners(out) == [yellow, blue, green, red])
    }

    @Test func counterClockwiseQuarter() throws {
        let out = try #require(ImageRotation.rotate(src, Rotation(quarterTurns: 3)))
        #expect(out.width == 20 && out.height == 40)
        #expect(corners(out) == [green, yellow, red, blue])
    }

    @Test func clockwiseThenCounterClockwiseRestoresImage() throws {
        let cw = try #require(ImageRotation.rotate(src, Rotation(quarterTurns: 1)))
        let back = try #require(ImageRotation.rotate(cw, Rotation(quarterTurns: 3)))
        #expect(back.width == 40 && back.height == 20)
        #expect(corners(back) == corners(src))
    }
}
