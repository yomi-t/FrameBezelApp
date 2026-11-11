import Testing
import CoreGraphics
@testable import FrameBezelApp

struct ScreenCropBasicsTests {
    private let screen = TestSupport.aperture(50, 100, 100, 200) // x=50,y=100,w=100,h=200
    private func clamp(_ c: ScreenCrop, sw: Double = 200, sh: Double = 100) -> ScreenCrop {
        c.clamped(screenshotWidth: sw, screenshotHeight: sh, screenWidth: 100, screenHeight: 200)
    }

    @Test func staticFitAndFill() {
        #expect(ScreenCrop.fill.zoom == 1)
        #expect(ScreenCrop.fit.zoom == 0)
        #expect(ScreenCrop.fill.offsetX == 0 && ScreenCrop.fill.offsetY == 0)
    }

    @Test func fitResolvesToTheContainZoom() {
        // 200x100 を 100x200 へ収める: 縮尺 0.5 vs 2 → fill 比 2 に対して 0.25
        #expect(clamp(.fit).zoom == 0.25)
    }

    @Test func fitIsOneWhenAspectsMatch() {
        #expect(clamp(.fit, sw: 50, sh: 100).zoom == 1)
    }

    @Test func zoomIsLimitedAboveAndBelow() {
        #expect(clamp(ScreenCrop(zoom: 99)).zoom == ScreenCrop.maxZoom)
        let fit = clamp(.fit).zoom
        #expect(abs(clamp(ScreenCrop(zoom: 0.0001)).zoom - fit * ScreenCrop.minScaleOfFit) < 1e-12)
    }

    @Test func degenerateSizesFallBackToSafeZoom() {
        let c = ScreenCrop(zoom: 0).clamped(screenshotWidth: 0, screenshotHeight: 0, screenWidth: 0, screenHeight: 0)
        #expect(c.zoom == 1)
        let big = ScreenCrop(zoom: 100).clamped(screenshotWidth: 0, screenshotHeight: 10, screenWidth: 10, screenHeight: 10)
        #expect(big.zoom == ScreenCrop.maxZoom)
    }

    @Test func offsetIsLimitedOnOverflowingAxisAndSmallAxisStaysInside() {
        // fill: 画像は 400x200（比 2）。幅方向に 300 はみ出し → 片側 150px = 0.5*(300/100)... 正規化 1.5? 実値で確認
        let c = clamp(ScreenCrop(zoom: 1, offsetX: 99, offsetY: 99))
        #expect(c.offsetX == 1.5)   // (400-100)/2/100
        #expect(c.offsetY == 0)     // 高さは窓と同じなので動かせない
        // 縮小時は窓の中に収まる範囲で動かせる: zoom 0.25 → 100x50、縦に (200-50)/2/200
        let s = clamp(ScreenCrop(zoom: 0.25, offsetX: 5, offsetY: 5))
        #expect(s.offsetX == 0)
        #expect(abs(s.offsetY - 0.375) < 1e-12)
    }

    @Test func imageRectAtFillCoversApertureCenteredAndOverflows() {
        let r = ScreenCrop.fill.imageRect(screenshotWidth: 200, screenshotHeight: 100, aperture: screen)
        #expect(r.height == 200 && r.width == 400)
        #expect(r.midX == 100 && r.midY == 200) // 窓の中心
    }

    @Test func imageRectFollowsOffsetAndZoom() {
        let r = ScreenCrop(zoom: 0.5, offsetX: 0.25, offsetY: -0.5).imageRect(screenshotWidth: 200, screenshotHeight: 100, aperture: screen)
        #expect(r.width == 200 && r.height == 100)
        #expect(r.midX == 125 && r.midY == 100)
    }

    @Test func heightEditKeepsCenterAndAspect() {
        let base = ScreenCrop.fill
        let c = base.withImageHeight(100, screenshotWidth: 200, screenshotHeight: 100, aperture: screen)
        let r = c.imageRect(screenshotWidth: 200, screenshotHeight: 100, aperture: screen)
        #expect(abs(r.height - 100) < 1e-9 && abs(r.width - 200) < 1e-9)
        #expect(abs(r.midX - 100) < 1e-9 && abs(r.midY - 200) < 1e-9)
    }

    @Test func nonPositiveSizeEditsAreIgnored() {
        let base = ScreenCrop(zoom: 0.8, offsetX: 0.1, offsetY: 0.1)
        #expect(base.withImageWidth(0, screenshotWidth: 200, screenshotHeight: 100, aperture: screen) == base)
        #expect(base.withImageWidth(-5, screenshotWidth: 200, screenshotHeight: 100, aperture: screen) == base)
        #expect(base.withImageHeight(0, screenshotWidth: 200, screenshotHeight: 100, aperture: screen) == base)
    }

    @Test func originEditKeepsSize() {
        let c = ScreenCrop(zoom: 0.5).withImageOrigin(x: 10, y: 20, screenshotWidth: 200, screenshotHeight: 100, aperture: screen)
        let r = c.imageRect(screenshotWidth: 200, screenshotHeight: 100, aperture: screen)
        #expect(c.zoom == 0.5)
        #expect(abs(r.minX - 60) < 1e-9 && abs(r.minY - 120) < 1e-9)
    }

    @Test func resizeWithInvalidInputsReturnsSelf() {
        let c = ScreenCrop(zoom: 1)
        #expect(c.resized(by: 2, anchor: .zero, screenshotWidth: 0, screenshotHeight: 100, aperture: screen) == c)
        let fit = ScreenCrop.fit // zoom 0 は未解決なので何もしない
        #expect(fit.resized(by: 2, anchor: .zero, screenshotWidth: 200, screenshotHeight: 100, aperture: screen) == fit)
    }

    @Test func resizeScalesAroundAnchor() {
        // 窓と同じ比の画像（半分の大きさ）を 2 倍にする。固定した点 (25,50) は動かない
        let a = TestSupport.aperture(0, 0, 100, 200)
        let c = ScreenCrop(zoom: 0.5).resized(by: 2, anchor: CGPoint(x: 25, y: 50), screenshotWidth: 100, screenshotHeight: 200, aperture: a)
        #expect(c.zoom == 1)
        let r = c.imageRect(screenshotWidth: 100, screenshotHeight: 200, aperture: a)
        #expect(abs(r.minX - 25) < 1e-9 && abs(r.minY - 50) < 1e-9) // 固定点が左上のまま、右下へ広がる
        #expect(abs(r.width - 100) < 1e-9 && abs(r.height - 200) < 1e-9)
    }
}

struct ScreenCropSnapTests {
    private let screen = TestSupport.aperture(0, 0, 100, 200)
    private let shot = (w: 100.0, h: 200.0)

    @Test func movingSnapsLeftEdgeAndTopEdgeIndependently() {
        // 窓と同サイズの画像を (2, 3) ずらした状態 → 閾値 5 なら両軸とも吸着
        let c = ScreenCrop(zoom: 1, offsetX: 0.02, offsetY: 3.0 / 200)
        let r = c.snappedPosition(screenshotWidth: shot.w, screenshotHeight: shot.h, aperture: screen, threshold: 5)
        #expect(r.snapped)
        #expect(abs(r.crop.offsetX) < 1e-12 && abs(r.crop.offsetY) < 1e-12)
    }

    @Test func movingSnapsOnlyTheNearAxis() {
        let c = ScreenCrop(zoom: 1, offsetX: 0.02, offsetY: 0.2) // y は 40px 離れている
        let r = c.snappedPosition(screenshotWidth: shot.w, screenshotHeight: shot.h, aperture: screen, threshold: 5)
        #expect(r.snapped)
        #expect(abs(r.crop.offsetX) < 1e-12)
        #expect(r.crop.offsetY == 0.2)
    }

    @Test func movingBeyondThresholdDoesNothing() {
        let c = ScreenCrop(zoom: 1, offsetX: 0.1, offsetY: 0.1)
        let r = c.snappedPosition(screenshotWidth: shot.w, screenshotHeight: shot.h, aperture: screen, threshold: 5)
        #expect(!r.snapped)
        #expect(r.crop == c)
    }

    @Test func smallImageSnapsItsEdgesToEachApertureEdge() {
        // 半分の大きさの画像 (50x100) を窓の右下隅の近くへ → 右辺・下辺が窓の右辺・下辺へ
        let c = ScreenCrop(zoom: 0.5, offsetX: 0.25 - 0.01, offsetY: 0.25 - 0.01)
        let r = c.snappedPosition(screenshotWidth: shot.w, screenshotHeight: shot.h, aperture: screen, threshold: 5)
        #expect(r.snapped)
        #expect(abs(r.crop.offsetX - 0.25) < 1e-12 && abs(r.crop.offsetY - 0.25) < 1e-12)
    }

    @Test func snapFactorSnapsWidthToApertureWidth() {
        // 左上を固定、右下の角 (50,100)(= 幅50) を動かす。倍率 1.98 → 幅 99 → 100 に吸着（倍率 2）
        let r = ScreenCrop.snapFactor(1.98, moved: CGPoint(x: 50, y: 100), anchor: .zero, aperture: screen, threshold: 3)
        #expect(r.snapped)
        #expect(abs(r.factor - 2) < 1e-12)
    }

    @Test func snapFactorLeavesFarValuesAlone() {
        let r = ScreenCrop.snapFactor(1.5, moved: CGPoint(x: 50, y: 100), anchor: .zero, aperture: screen, threshold: 3)
        #expect(!r.snapped && r.factor == 1.5)
    }

    @Test func snapFactorPicksTheNearestCandidate() {
        let r = ScreenCrop.snapFactor(2.01, moved: CGPoint(x: 50, y: 100), anchor: .zero, aperture: screen, threshold: 10)
        #expect(abs(r.factor - 2) < 1e-12)
    }

    @Test func snapFactorIgnoresNegativeOrZeroFactors() {
        // 角が固定点の反対側へ越える候補（負の倍率）は採用しない
        let r = ScreenCrop.snapFactor(0.01, moved: CGPoint(x: 50, y: 100), anchor: CGPoint(x: 0, y: 0), aperture: TestSupport.aperture(-1, -1, 2, 2), threshold: 100)
        #expect(r.factor > 0)
    }

    @Test func snapFactorWithZeroSizedSelectionDoesNotCrash() {
        let r = ScreenCrop.snapFactor(1, moved: .zero, anchor: .zero, aperture: screen, threshold: 5)
        #expect(!r.snapped && r.factor == 1)
    }
}
