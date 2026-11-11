import Foundation
import Testing
import CoreGraphics
@testable import FrameBezelApp

struct ComposerTests {
    typealias RGBA = TestSupport.RGBA
    private let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    private let green = RGBA(r: 0, g: 255, b: 0, a: 255)
    private let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
    private let yellow = RGBA(r: 255, g: 255, b: 0, a: 255)
    private let black = RGBA(r: 0, g: 0, b: 0, a: 255)

    /// 100x200 のベゼル。画面領域は (20,20) 60x160。
    private let bezel = TestSupport.bezel(width: 100, height: 200,
                                          aperture: TestSupport.aperture(20, 20, 60, 160))
    private var frameImage: CGImage {
        TestSupport.bezelImage(width: 100, height: 200, screen: CGRect(x: 20, y: 20, width: 60, height: 160), outerCornerClear: true)
    }
    /// 何も描かれていない（全面透明）ベゼル画像。背景やスクショだけを見たいときに使う。
    private func clearImage(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: TestSupport.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
    private func settings(_ bg: BackgroundStyle = .transparent) -> ComposeSettings { ComposeSettings(background: bg) }

    // MARK: outputSize

    @Test func outputSizeIsBezelSizeAtScaleOne() {
        let s = Composer.outputSize(bezel: bezel)
        #expect(s.width == 100 && s.height == 200)
    }

    @Test func outputSizeScalesAndRounds() {
        let s = Composer.outputSize(bezel: bezel, scale: 0.25)
        #expect(s.width == 25 && s.height == 50)
        let r = Composer.outputSize(bezel: bezel, scale: 0.333)
        #expect(r.width == 33 && r.height == 67)
    }

    @Test func outputSizeNeverCollapsesToZero() {
        let s = Composer.outputSize(bezel: bezel, scale: 0)
        #expect(s.width >= 1 && s.height >= 1)
        let t = Composer.outputSize(bezel: TestSupport.bezel(width: 1, height: 1), scale: 0.01)
        #expect(t.width == 1 && t.height == 1)
    }

    // MARK: compose

    @Test func fillMapsScreenshotQuadrantsOntoTheScreen() throws {
        let out = try Composer.compose(screenshot: TestSupport.quadrants(60, 160), bezel: bezel, bezelImage: frameImage,
                                       settings: settings(), crop: .fill)
        #expect(out.width == 100 && out.height == 200)
        #expect(TestSupport.pixel(out, 25, 25) == red)
        #expect(TestSupport.pixel(out, 75, 25) == green)
        #expect(TestSupport.pixel(out, 25, 175) == blue)
        #expect(TestSupport.pixel(out, 75, 175) == yellow)
    }

    @Test func bezelIsDrawnOnTopOfTheScreenshot() throws {
        let out = try Composer.compose(screenshot: TestSupport.solid(60, 160), bezel: bezel, bezelImage: frameImage,
                                       settings: settings(), crop: .fill)
        #expect(TestSupport.pixel(out, 10, 100) == black) // 枠の中
        #expect(TestSupport.pixel(out, 50, 100) == red)   // 窓の中
    }

    @Test func transparentBackgroundLeavesOuterCornersTransparent() throws {
        let out = try Composer.compose(screenshot: TestSupport.solid(60, 160), bezel: bezel, bezelImage: frameImage,
                                       settings: settings(.transparent), crop: .fill)
        #expect(TestSupport.pixel(out, 0, 0).a == 0)
        #expect(TestSupport.pixel(out, 99, 199).a == 0)
    }

    @Test func solidBackgroundShowsThroughTransparentFrame() throws {
        let bg = BackgroundStyle.solid(RGBAColor(r: 0, g: 0, b: 1))
        let out = try Composer.compose(screenshot: TestSupport.solid(60, 160), bezel: bezel, bezelImage: frameImage,
                                       settings: settings(bg), crop: .fill)
        #expect(TestSupport.pixel(out, 0, 0) == blue)
    }

    @Test func horizontalGradientRunsLeftToRight() throws {
        let b = TestSupport.bezel(width: 100, height: 100, aperture: TestSupport.aperture(40, 40, 20, 20))
        let bg = BackgroundStyle.gradient(start: RGBAColor(r: 1, g: 0, b: 0), end: RGBAColor(r: 0, g: 0, b: 1), angleDegrees: 0)
        let out = try Composer.compose(screenshot: TestSupport.solid(20, 20, r: 0, g: 1, b: 0), bezel: b,
                                       bezelImage: clearImage(100, 100), settings: settings(bg), crop: .fill)
        let left = TestSupport.pixel(out, 1, 5), right = TestSupport.pixel(out, 98, 5)
        #expect(left.r > 240 && left.b < 15)
        #expect(right.b > 240 && right.r < 15)
        // 同じ列は上下で同じ色（水平グラデーション）
        #expect(TestSupport.pixel(out, 5, 1) == TestSupport.pixel(out, 5, 98))
    }

    @Test func verticalGradientRunsTopToBottom() throws {
        let b = TestSupport.bezel(width: 100, height: 100, aperture: TestSupport.aperture(40, 40, 20, 20))
        let bg = BackgroundStyle.gradient(start: RGBAColor(r: 1, g: 0, b: 0), end: RGBAColor(r: 0, g: 0, b: 1), angleDegrees: 90)
        let out = try Composer.compose(screenshot: TestSupport.solid(20, 20, r: 0, g: 1, b: 0), bezel: b,
                                       bezelImage: clearImage(100, 100), settings: settings(bg), crop: .fill)
        let top = TestSupport.pixel(out, 5, 1), bottom = TestSupport.pixel(out, 5, 98)
        #expect(top.r > 240 && top.b < 15)
        #expect(bottom.b > 240 && bottom.r < 15)
    }

    @Test func fitLeavesBlackLetterboxInsideScreen() throws {
        // 横長 120x60 を 60x160 の窓へ「収める」: 幅いっぱいの 60x30 が中央に入り、上下は黒
        let b = TestSupport.bezel(width: 100, height: 200, aperture: TestSupport.aperture(20, 20, 60, 160))
        let out = try Composer.compose(screenshot: TestSupport.solid(120, 60), bezel: b, bezelImage: clearImage(100, 200),
                                       settings: settings(), crop: .fit)
        #expect(TestSupport.pixel(out, 50, 100) == red)
        #expect(TestSupport.pixel(out, 50, 30) == black) // 窓の上部の余白
        #expect(TestSupport.pixel(out, 50, 170) == black)
        #expect(TestSupport.pixel(out, 5, 5).a == 0)      // 窓の外には何も描かれない
    }

    @Test func offsetShiftsTheVisiblePartOfAnOverflowingScreenshot() throws {
        // 120x160 を 60x160 の窓へ埋める。中央寄せでは左半分が赤/青、右半分が緑/黄。右へ最大移動すると画像の左端が見える
        let shot = TestSupport.quadrants(120, 160)
        let centered = try Composer.compose(screenshot: shot, bezel: bezel, bezelImage: clearImage(100, 200),
                                            settings: settings(), crop: .fill)
        #expect(TestSupport.pixel(centered, 25, 25) == red)
        #expect(TestSupport.pixel(centered, 75, 25) == green)
        let shifted = try Composer.compose(screenshot: shot, bezel: bezel, bezelImage: clearImage(100, 200),
                                           settings: settings(), crop: ScreenCrop(zoom: 1, offsetX: 0.5, offsetY: 0))
        #expect(TestSupport.pixel(shifted, 75, 25) == red)
        let other = try Composer.compose(screenshot: shot, bezel: bezel, bezelImage: clearImage(100, 200),
                                         settings: settings(), crop: ScreenCrop(zoom: 1, offsetX: -0.5, offsetY: 0))
        #expect(TestSupport.pixel(other, 25, 25) == green)
    }

    @Test func offsetBeyondLimitIsClamped() throws {
        let shot = TestSupport.quadrants(120, 160)
        let out = try Composer.compose(screenshot: shot, bezel: bezel, bezelImage: clearImage(100, 200),
                                       settings: settings(), crop: ScreenCrop(zoom: 1, offsetX: 9, offsetY: 9))
        // 範囲外の指定でも黒い隙間が出ない（画面領域は画像で埋まっている）
        #expect(TestSupport.pixel(out, 21, 21) != black)
        #expect(TestSupport.pixel(out, 78, 178) != black)
    }

    @Test func smallerThanScreenShowsBlackAroundIt() throws {
        // 縮小 (zoom 0.5) すると画面領域の周囲が黒になる
        let out = try Composer.compose(screenshot: TestSupport.solid(60, 160), bezel: bezel, bezelImage: clearImage(100, 200),
                                       settings: settings(), crop: ScreenCrop(zoom: 0.5))
        #expect(TestSupport.pixel(out, 50, 100) == red)
        #expect(TestSupport.pixel(out, 22, 22) == black)
    }

    @Test func roundedApertureClipsScreenshotAndUnderlay() throws {
        let b = TestSupport.bezel(width: 100, height: 100, aperture: TestSupport.aperture(10, 10, 80, 80, r: 30))
        let out = try Composer.compose(screenshot: TestSupport.solid(80, 80), bezel: b, bezelImage: clearImage(100, 100),
                                       settings: settings(), crop: .fill)
        #expect(TestSupport.pixel(out, 11, 11).a == 0)   // 角の外は切り抜かれる
        #expect(TestSupport.pixel(out, 50, 50) == red)
        #expect(TestSupport.pixel(out, 50, 11) == red)   // 辺の中ほどは丸みの影響なし
    }

    @Test func oversizedCornerRadiusIsLimitedToHalfTheShortSide() throws {
        let b = TestSupport.bezel(width: 100, height: 100, aperture: TestSupport.aperture(10, 10, 80, 40, r: 500))
        let out = try Composer.compose(screenshot: TestSupport.solid(80, 40), bezel: b, bezelImage: clearImage(100, 100),
                                       settings: settings(), crop: .fill)
        #expect(TestSupport.pixel(out, 50, 30) == red) // 中心は描かれる
    }

    @Test func previewScaleKeepsLayoutProportional() throws {
        let out = try Composer.compose(screenshot: TestSupport.quadrants(60, 160), bezel: bezel, bezelImage: frameImage,
                                       settings: settings(), crop: .fill, scale: 0.5)
        #expect(out.width == 50 && out.height == 100)
        #expect(TestSupport.pixel(out, 12, 12) == red)
        #expect(TestSupport.pixel(out, 37, 12) == green)
        #expect(TestSupport.pixel(out, 12, 87) == blue)
        #expect(TestSupport.pixel(out, 37, 87) == yellow)
        #expect(TestSupport.pixel(out, 2, 50) == black)
    }

    @Test func composeKeepsAlphaForTransparentBackground() throws {
        let out = try Composer.compose(screenshot: TestSupport.solid(60, 160), bezel: bezel, bezelImage: frameImage,
                                       settings: settings())
        #expect(out.alphaInfo != .none && out.alphaInfo != .noneSkipFirst && out.alphaInfo != .noneSkipLast)
    }
}

struct ComposeFittedTests {
    typealias RGBA = TestSupport.RGBA
    private let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    private let white = RGBA(r: 255, g: 255, b: 255, a: 255)
    private let blue = RGBA(r: 0, g: 0, b: 255, a: 255)

    private let bezel = TestSupport.bezel(width: 100, height: 200, aperture: TestSupport.aperture(10, 10, 80, 180))
    private var bezelImage: CGImage { TestSupport.bezelImage(width: 100, height: 200, screen: CGRect(x: 10, y: 10, width: 80, height: 180)) }
    private func fitted(_ canvas: (Int, Int), bg: BackgroundStyle = .transparent, crop: ScreenCrop = .fill) throws -> CGImage {
        try Composer.composeFitted(screenshot: TestSupport.solid(80, 180), bezel: bezel, bezelImage: bezelImage,
                                   settings: ComposeSettings(background: bg), crop: crop, canvas: canvas)
    }

    @Test func transparentBackgroundBecomesWhiteMargins() throws {
        let out = try fitted((1000, 1000))
        #expect(TestSupport.pixel(out, 10, 500) == white)
        #expect(TestSupport.pixel(out, 990, 500) == white)
    }

    @Test func tallCanvasIsLetterboxedTopAndBottom() throws {
        // 100x200 → 1000x2000 の比と違う 1000x3000: 倍率 10、上下に 500px ずつ余白
        let out = try fitted((1000, 3000), bg: .solid(RGBAColor(r: 0, g: 0, b: 1)))
        #expect(TestSupport.pixel(out, 500, 100) == blue)
        #expect(TestSupport.pixel(out, 500, 2900) == blue)
        #expect(TestSupport.pixel(out, 500, 1500) == red)
        #expect(TestSupport.pixel(out, 500, 520).r == 0) // ベゼル（黒）の始まり
    }

    @Test func wideCanvasIsPillarboxed() throws {
        // 2000x400: 倍率 2 → 200x400 が中央（左右 900px の余白）
        let out = try fitted((2000, 400), bg: .solid(RGBAColor(r: 0, g: 0, b: 1)))
        #expect(TestSupport.pixel(out, 100, 200) == blue)
        #expect(TestSupport.pixel(out, 1900, 200) == blue)
        #expect(TestSupport.pixel(out, 1000, 200) == red)
    }

    @Test func downscalesWhenCanvasIsSmallerThanBezel() throws {
        let out = try fitted((50, 100))
        #expect(out.width == 50 && out.height == 100)
        #expect(TestSupport.pixel(out, 25, 50) == red)
    }

    @Test func semiTransparentBackgroundStillProducesOpaqueOutput() throws {
        let out = try fitted((1000, 1000), bg: .solid(RGBAColor(r: 0, g: 0, b: 1, a: 0.5)))
        let p = TestSupport.pixel(out, 10, 500)
        #expect(p.a == 255)
        #expect(p.r > 100 && p.b == 255) // 白と青の中間
        #expect(out.alphaInfo == .noneSkipFirst)
    }

    @Test func gradientBackgroundFillsTheWholeCanvas() throws {
        let bg = BackgroundStyle.gradient(start: RGBAColor(r: 1, g: 0, b: 0), end: RGBAColor(r: 0, g: 0, b: 1), angleDegrees: 0)
        let out = try fitted((2000, 400), bg: bg)
        let l = TestSupport.pixel(out, 2, 200), r = TestSupport.pixel(out, 1997, 200)
        #expect(l.r > 240 && l.b < 15)
        #expect(r.b > 240 && r.r < 15)
    }

    @Test func cropIsAppliedInsideTheScaledBezel() throws {
        // 画面領域の外周を黒にできる縮小。キャンバス上でも黒帯が拡大される
        let out = try fitted((1000, 2000), crop: ScreenCrop(zoom: 0.5))
        #expect(TestSupport.pixel(out, 500, 1000) == red)
        #expect(TestSupport.pixel(out, 150, 1000).r == 0)
    }

    @Test func invalidCanvasThrows() {
        #expect(throws: ComposeError.self) { try fitted((0, 100)) }
        #expect(throws: ComposeError.self) { try fitted((100, 0)) }
    }

    @Test func writtenPNGHasNoAlphaChannel() throws {
        let dir = try TestSupport.makeTempDirectory(); defer { TestSupport.remove(dir) }
        let url = dir.appendingPathComponent("o.png")
        try ImageFile.writePNG(fitted((300, 300)), to: url)
        let bytes = try Data(contentsOf: url)
        #expect(bytes[25] == 2) // IHDR の色タイプ 2 = RGB（6 なら RGBA）
    }
}

struct ComposeSettingsCodingTests {
    @Test func backgroundStylesRoundTripThroughJSON() throws {
        let styles: [BackgroundStyle] = [.transparent, .solid(RGBAColor(r: 0.2, g: 0.4, b: 0.6, a: 0.8)),
                                         .gradient(start: RGBAColor(r: 0, g: 0, b: 0), end: RGBAColor(r: 1, g: 1, b: 1), angleDegrees: 33)]
        for s in styles {
            let data = try JSONEncoder().encode(ComposeSettings(background: s))
            #expect(try JSONDecoder().decode(ComposeSettings.self, from: data).background == s)
        }
    }

    @Test func rgbaColorDefaultsToOpaque() {
        #expect(RGBAColor(r: 0, g: 0, b: 0).a == 1)
    }
}
