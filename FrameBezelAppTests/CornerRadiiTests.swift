import Testing
import Foundation
import CoreGraphics
@testable import FrameBezelApp

struct CornerRadiiTests {
    private let mixed = CornerRadii(topLeft: 24, topRight: 174, bottomRight: 174, bottomLeft: 24)

    @Test func uniformAndAverage() {
        let u = CornerRadii(uniform: 30)
        #expect(u.isUniform && u.average == 30)
        #expect(!mixed.isUniform && mixed.average == 99)
    }

    @Test func clockwiseTurnMovesEachCornerToTheNextOne() {
        let r = CornerRadii(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4)
        let cw = r.rotatedClockwise() // 左上だった角は右上へ
        #expect(cw == CornerRadii(topLeft: 4, topRight: 1, bottomRight: 2, bottomLeft: 3))
        let ccw = r.rotatedCounterClockwise() // 左上だった角は左下へ
        #expect(ccw == CornerRadii(topLeft: 2, topRight: 3, bottomRight: 4, bottomLeft: 1))
    }

    @Test func turningBackAndForthRestoresTheOriginal() {
        let r = CornerRadii(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4)
        #expect(r.rotatedClockwise().rotatedCounterClockwise() == r)
        #expect(r.rotatedCounterClockwise().rotatedClockwise() == r)
        var x = r
        for _ in 0..<4 { x = x.rotatedClockwise() }
        #expect(x == r)
    }

    @Test func appleDuoPortraitRotatesIntoAppleDuoLandscape() {
        // Duo の外側の画面を実測した値（縦: 24/174/174/24、横: 174/174/24/24）。縦を反時計回りに回すと横になる
        let landscape = CornerRadii(topLeft: 174, topRight: 174, bottomRight: 24, bottomLeft: 24)
        #expect(mixed.rotatedCounterClockwise() == landscape)
        #expect(landscape.rotatedClockwise() == mixed)
    }

    @Test func fittedShrinksOnlyWhenNeighborsOverflowASide() {
        let ok = CornerRadii(topLeft: 10, topRight: 20, bottomRight: 30, bottomLeft: 40).fitted(width: 100, height: 100)
        #expect(ok == CornerRadii(topLeft: 10, topRight: 20, bottomRight: 30, bottomLeft: 40))
        let big = CornerRadii(uniform: 80).fitted(width: 100, height: 100) // 80+80 > 100
        #expect(big == CornerRadii(uniform: 50))
        let wide = CornerRadii(uniform: 60).fitted(width: 400, height: 100) // 高さに合わせて 50 に
        #expect(wide == CornerRadii(uniform: 50))
    }

    @Test func fittedNeverReturnsNegativeOrNaN() {
        let z = CornerRadii(uniform: 0).fitted(width: 0, height: 0)
        #expect(z == CornerRadii(uniform: 0))
        let neg = CornerRadii(topLeft: -5, topRight: 5, bottomRight: 5, bottomLeft: 5).fitted(width: 100, height: 100)
        #expect(neg.topLeft == 0)
    }

    @Test func jsonRoundTripAndLegacyApertureWithoutRadii() throws {
        let a = Aperture(x: 1, y: 2, width: 3, height: 4, cornerRadius: 99, cornerRadii: mixed)
        let data = try JSONEncoder().encode(a)
        #expect(try JSONDecoder().decode(Aperture.self, from: data) == a)
        let legacy = #"{"x":1,"y":2,"width":3,"height":4,"cornerRadius":12}"#
        let old = try JSONDecoder().decode(Aperture.self, from: Data(legacy.utf8))
        #expect(old.cornerRadii == nil && old.cornerRadius == 12)
        #expect(old.radii == CornerRadii(uniform: 12))
        // 角ごとの指定が無いデータは、保存し直しても余計な項目を増やさない
        let reencoded = String(data: try JSONEncoder().encode(old), encoding: .utf8) ?? ""
        #expect(!reencoded.contains("cornerRadii"))
    }

    @Test func radiiFallBackToUniformCornerRadius() {
        #expect(Aperture(x: 0, y: 0, width: 10, height: 10, cornerRadius: 7).radii == CornerRadii(uniform: 7))
        #expect(Aperture(x: 0, y: 0, width: 10, height: 10, cornerRadius: 7, cornerRadii: mixed).radii == mixed)
    }
}

struct ClipPathTests {
    /// 100x100 の矩形（CG 座標）。左上だけ半径 40、他は直角。
    private func path(_ radii: CornerRadii) -> CGPath {
        Aperture(x: 0, y: 0, width: 100, height: 100, cornerRadius: 0, cornerRadii: radii).clipPath(in: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func onlyTheRoundedCornerIsCutAway() {
        let p = path(CornerRadii(topLeft: 40, topRight: 0, bottomRight: 0, bottomLeft: 0))
        // CG は y 上向き: 画像の左上 = (0, 100) の角
        #expect(!p.contains(CGPoint(x: 2, y: 98)))   // 左上の角は丸く切れている
        #expect(p.contains(CGPoint(x: 98, y: 98)))   // 右上は直角
        #expect(p.contains(CGPoint(x: 98, y: 2)))    // 右下
        #expect(p.contains(CGPoint(x: 2, y: 2)))     // 左下
        #expect(p.contains(CGPoint(x: 50, y: 50)))
    }

    @Test func eachCornerIsIndependent() {
        for (radii, outside) in [
            (CornerRadii(topLeft: 40, topRight: 0, bottomRight: 0, bottomLeft: 0), CGPoint(x: 2, y: 98)),
            (CornerRadii(topLeft: 0, topRight: 40, bottomRight: 0, bottomLeft: 0), CGPoint(x: 98, y: 98)),
            (CornerRadii(topLeft: 0, topRight: 0, bottomRight: 40, bottomLeft: 0), CGPoint(x: 98, y: 2)),
            (CornerRadii(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 40), CGPoint(x: 2, y: 2)),
        ] {
            #expect(!path(radii).contains(outside))
        }
    }

    @Test func uniformRadiiMatchTheOldRoundedRect() {
        let a = path(CornerRadii(uniform: 30))
        let b = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100), cornerWidth: 30, cornerHeight: 30, transform: nil)
        for x in stride(from: 1.0, to: 100.0, by: 7) {
            for y in stride(from: 1.0, to: 100.0, by: 7) {
                #expect(a.contains(CGPoint(x: x, y: y)) == b.contains(CGPoint(x: x, y: y)), "(\(x), \(y))")
            }
        }
    }

    @Test func zeroRadiiGiveAPlainRectangle() {
        let p = path(CornerRadii(uniform: 0))
        #expect(p.contains(CGPoint(x: 0.5, y: 0.5)) && p.contains(CGPoint(x: 99.5, y: 99.5)))
        #expect(p.boundingBox == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func oversizedRadiiAreShrunkToFit() {
        let p = path(CornerRadii(uniform: 500))
        #expect(p.boundingBox.width == 100 && p.boundingBox.height == 100)
        #expect(p.contains(CGPoint(x: 50, y: 50)))
        #expect(!p.contains(CGPoint(x: 3, y: 3)))
    }
}

struct DetectorCornerRadiiTests {
    private let screen = CGRect(x: 40, y: 40, width: 400, height: 600)

    @Test func detectsDifferentRadiiPerCorner() throws {
        let radii = CornerRadii(topLeft: 24, topRight: 174, bottomRight: 174, bottomLeft: 24)
        let a = try BezelDetector.detect(image: TestSupport.bezelImage(width: 480, height: 680, screen: screen, radii: radii))
        let found = try #require(a.cornerRadii)
        #expect(abs(found.topLeft - 24) <= 6 && abs(found.bottomLeft - 24) <= 6)
        #expect(abs(found.topRight - 174) <= 12 && abs(found.bottomRight - 174) <= 12)
        #expect(a.width == 400 && a.height == 600)
        #expect(abs(a.cornerRadius - radii.average) <= 10) // 共通の値は平均
    }

    @Test func eachCornerKeepsItsOwnPosition() throws {
        for (radii, index) in [(CornerRadii(topLeft: 80, topRight: 0, bottomRight: 0, bottomLeft: 0), 0),
                               (CornerRadii(topLeft: 0, topRight: 80, bottomRight: 0, bottomLeft: 0), 1),
                               (CornerRadii(topLeft: 0, topRight: 0, bottomRight: 80, bottomLeft: 0), 2),
                               (CornerRadii(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 80), 3)] {
            let a = try BezelDetector.detect(image: TestSupport.bezelImage(width: 480, height: 680, screen: screen, radii: radii))
            let f = try #require(a.cornerRadii)
            let values = [f.topLeft, f.topRight, f.bottomRight, f.bottomLeft]
            #expect(values[index] > 60, "corner \(index): \(values)")
            #expect(values.enumerated().allSatisfy { $0.offset == index || $0.element < 10 }, "corner \(index): \(values)")
        }
    }

    @Test func uniformWindowStaysUniform() throws {
        let a = try BezelDetector.detect(image: TestSupport.bezelImage(width: 480, height: 680, screen: screen, radii: CornerRadii(uniform: 60)))
        #expect(a.cornerRadii == nil)
        #expect(abs(a.cornerRadius - 60) <= 6)
    }

    @Test func rectangularWindowHasNoRadii() throws {
        let a = try BezelDetector.detect(image: TestSupport.bezelImage(width: 480, height: 680, screen: screen))
        #expect(a.cornerRadii == nil && a.cornerRadius == 0)
    }

    @Test func detectionOfARotatedImageMatchesTheRotatedRadii() throws {
        // 画像を実際に反時計回りに回して検出した角丸が、`rotatedCounterClockwise` の計算と一致する
        let radii = CornerRadii(topLeft: 24, topRight: 174, bottomRight: 174, bottomLeft: 24)
        let image = TestSupport.bezelImage(width: 480, height: 680, screen: screen, radii: radii)
        let rotated = try #require(ImageRotation.rotate(image, Rotation(quarterTurns: 3)))
        let measured = try #require(try BezelDetector.detect(image: rotated).cornerRadii)
        let expected = radii.rotatedCounterClockwise()
        #expect(abs(measured.topLeft - expected.topLeft) <= 12 && abs(measured.topRight - expected.topRight) <= 12)
        #expect(abs(measured.bottomRight - expected.bottomRight) <= 8 && abs(measured.bottomLeft - expected.bottomLeft) <= 8)
    }
}

struct ComposerCornerRadiiTests {
    private let red = TestSupport.RGBA(r: 255, g: 0, b: 0, a: 255)

    /// 100x100 の何も描かれていないベゼル画像に、角ごとに違う角丸の画面領域をあてがって合成する
    private func compose(_ radii: CornerRadii) throws -> CGImage {
        let ctx = CGContext(data: nil, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                            space: TestSupport.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let clear = ctx.makeImage()!
        let bezel = TestSupport.bezel(width: 120, height: 120,
                                      aperture: Aperture(x: 10, y: 10, width: 100, height: 100, cornerRadius: 0, cornerRadii: radii))
        return try Composer.compose(screenshot: TestSupport.solid(100, 100), bezel: bezel, bezelImage: clear,
                                    settings: ComposeSettings(background: .transparent), crop: .fill)
    }

    @Test func onlyTheRoundedCornersAreClipped() throws {
        let out = try compose(CornerRadii(topLeft: 40, topRight: 0, bottomRight: 40, bottomLeft: 0))
        #expect(TestSupport.pixel(out, 12, 12).a == 0)        // 左上は丸く切れる
        #expect(TestSupport.pixel(out, 107, 107).a == 0)      // 右下も
        #expect(TestSupport.pixel(out, 107, 12) == red)       // 右上は直角のまま
        #expect(TestSupport.pixel(out, 12, 107) == red)       // 左下も
        #expect(TestSupport.pixel(out, 60, 60) == red)
    }

    @Test func duoStyleOuterScreenHasSmallLeftAndLargeRightCorners() throws {
        let out = try compose(CornerRadii(topLeft: 10, topRight: 45, bottomRight: 45, bottomLeft: 10))
        #expect(TestSupport.pixel(out, 14, 14) == red)         // 左側は小さい丸み: 角のすぐ内側まで塗られる
        #expect(TestSupport.pixel(out, 14, 105) == red)
        #expect(TestSupport.pixel(out, 105, 14).a == 0)        // 右側は大きい丸み: 同じ位置はまだ切れている
        #expect(TestSupport.pixel(out, 105, 105).a == 0)
    }

    @Test func uniformRadiusKeepsWorkingLikeBefore() throws {
        let ctx = CGContext(data: nil, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                            space: TestSupport.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bezel = TestSupport.bezel(width: 120, height: 120, aperture: TestSupport.aperture(10, 10, 100, 100, r: 40))
        let out = try Composer.compose(screenshot: TestSupport.solid(100, 100), bezel: bezel, bezelImage: ctx.makeImage()!,
                                       settings: ComposeSettings(background: .transparent), crop: .fill)
        for (x, y) in [(12, 12), (107, 12), (12, 107), (107, 107)] { #expect(TestSupport.pixel(out, x, y).a == 0, "(\(x), \(y))") }
        #expect(TestSupport.pixel(out, 60, 60) == red)
    }

    @Test func composeFittedAlsoUsesPerCornerRadii() throws {
        let ctx = CGContext(data: nil, width: 120, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                            space: TestSupport.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bezel = TestSupport.bezel(width: 120, height: 120,
                                      aperture: Aperture(x: 10, y: 10, width: 100, height: 100, cornerRadius: 0,
                                                         cornerRadii: CornerRadii(topLeft: 0, topRight: 50, bottomRight: 0, bottomLeft: 0)))
        let out = try Composer.composeFitted(screenshot: TestSupport.solid(100, 100), bezel: bezel, bezelImage: ctx.makeImage()!,
                                             settings: ComposeSettings(background: .solid(RGBAColor(r: 0, g: 0, b: 1))), crop: .fill,
                                             canvas: (480, 480))
        // 4 倍に拡大: 右上の窓の角(430, 50 付近)は背景の青、左上(50, 50 付近)はスクショの赤
        #expect(TestSupport.pixel(out, 430, 50) == .init(r: 0, g: 0, b: 255, a: 255))
        #expect(TestSupport.pixel(out, 50, 50) == red)
    }
}

struct TurnedBezelCornerRadiiTests {
    private let radii = CornerRadii(topLeft: 24, topRight: 174, bottomRight: 174, bottomLeft: 24)
    private var portrait: Bezel {
        TestSupport.bezel(width: 200, height: 300,
                          aperture: Aperture(x: 10, y: 20, width: 150, height: 250, cornerRadius: 99, cornerRadii: radii),
                          orientation: .portrait)
    }

    @Test func turningToLandscapeRotatesTheCornersCounterClockwise() {
        let l = portrait.turned(to: .landscape)
        #expect(l.aperture.cornerRadii == radii.rotatedCounterClockwise())
        #expect(l.aperture.cornerRadii == CornerRadii(topLeft: 174, topRight: 174, bottomRight: 24, bottomLeft: 24))
        #expect(l.aperture.cornerRadius == 99)
    }

    @Test func turningThereAndBackRestoresTheCorners() {
        #expect(portrait.turned(to: .landscape).turned(to: .portrait) == portrait)
    }

    @Test func clockwiseTurnFromLandscapeRotatesTheCornersClockwise() {
        let landscape = TestSupport.bezel(width: 300, height: 200,
                                          aperture: Aperture(x: 20, y: 10, width: 250, height: 150, cornerRadius: 99,
                                                             cornerRadii: radii.rotatedCounterClockwise()),
                                          orientation: .landscape)
        #expect(landscape.turned(to: .portrait).aperture.cornerRadii == radii)
    }

    @Test func uniformBezelsKeepNoPerCornerData() {
        let b = TestSupport.bezel(width: 200, height: 300, aperture: TestSupport.aperture(10, 20, 150, 250, r: 30), orientation: .portrait)
        #expect(b.turned(to: .landscape).aperture.cornerRadii == nil)
        #expect(b.turned(to: .landscape).aperture.cornerRadius == 30)
    }

    @Test func turnedGeometryMatchesADetectionOfTheActuallyRotatedImage() throws {
        let screen = CGRect(x: 40, y: 40, width: 400, height: 600)
        let image = TestSupport.bezelImage(width: 480, height: 680, screen: screen, radii: radii)
        let registered = TestSupport.bezel(width: 480, height: 680, aperture: try BezelDetector.detect(image: image), orientation: .portrait)
        let rotated = try #require(ImageRotation.rotate(image, Rotation(quarterTurns: registered.quarterTurns(to: .landscape))))
        let detected = try #require(try BezelDetector.detect(image: rotated).cornerRadii)
        let calculated = try #require(registered.turned(to: .landscape).aperture.cornerRadii)
        #expect(abs(detected.topLeft - calculated.topLeft) <= 12 && abs(detected.topRight - calculated.topRight) <= 12)
        #expect(abs(detected.bottomRight - calculated.bottomRight) <= 10 && abs(detected.bottomLeft - calculated.bottomLeft) <= 10)
    }
}
