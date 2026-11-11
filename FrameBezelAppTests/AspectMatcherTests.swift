import Testing
@testable import FrameBezelApp

struct AspectMatcherTests {
    private let portrait = TestSupport.aperture(1179, 2556) // 画面領域: 幅1179 高さ2556

    @Test func identicalAspectHasZeroDifference() throws {
        let d = try #require(AspectMatcher.relativeDifference(screenshotWidth: 1179, screenshotHeight: 2556, aperture: portrait))
        #expect(d == 0)
    }

    @Test func scaledScreenshotStillMatches() {
        #expect(AspectMatcher.matches(screenshotWidth: 590, screenshotHeight: 1278, aperture: portrait))
    }

    @Test func nonPositiveSizesCannotBeCompared() {
        #expect(AspectMatcher.relativeDifference(screenshotWidth: 0, screenshotHeight: 100, aperture: portrait) == nil)
        #expect(AspectMatcher.relativeDifference(screenshotWidth: 100, screenshotHeight: -1, aperture: portrait) == nil)
        #expect(AspectMatcher.relativeDifference(screenshotWidth: 100, screenshotHeight: 100, aperture: TestSupport.aperture(0, 0)) == nil)
        #expect(!AspectMatcher.matches(screenshotWidth: 0, screenshotHeight: 0, aperture: portrait))
    }

    @Test func toleranceBoundary() {
        let a = TestSupport.aperture(100, 100)
        // 浮動小数点の誤差を避けるため境界のすぐ内側と外側で確かめる
        #expect(AspectMatcher.matches(screenshotWidth: 1009, screenshotHeight: 1000, aperture: a))
        #expect(!AspectMatcher.matches(screenshotWidth: 1011, screenshotHeight: 1000, aperture: a))
        #expect(!AspectMatcher.matches(screenshotWidth: 102, screenshotHeight: 100, aperture: a))
        #expect(AspectMatcher.matches(screenshotWidth: 102, screenshotHeight: 100, aperture: a, tolerance: 0.05))
    }

    @Test func rotatedScreenshotDoesNotMatchWithoutRotation() {
        #expect(!AspectMatcher.matches(screenshotWidth: 2556, screenshotHeight: 1179, aperture: portrait))
    }

    // MARK: suggestionsAllowingRotation

    private func bezel(_ file: String, _ w: Double, _ h: Double) -> Bezel {
        TestSupport.bezel(name: file, file: file, aperture: TestSupport.aperture(w, h))
    }

    @Test func suggestsDirectAndRotatedMatches() {
        let list = [bezel("p", 1179, 2556), bezel("l", 2556, 1179), bezel("sq", 1000, 1000)]
        let s = AspectMatcher.suggestionsAllowingRotation(screenshotWidth: 1179, screenshotHeight: 2556, from: list)
        #expect(s.map(\.bezel.bezelFile) == ["p", "l"])
        #expect(s.map(\.needsRotation) == [false, true])
    }

    @Test func excludesSelectedBezelFromDirectButKeepsItForRotation() {
        let list = [bezel("p", 1179, 2556)]
        // 横長スクショ + 縦ベゼル選択中: 回転すれば合う提案に選択中自身が出る
        let rot = AspectMatcher.suggestionsAllowingRotation(screenshotWidth: 2556, screenshotHeight: 1179, from: list, excluding: "p")
        #expect(rot.count == 1 && rot[0].needsRotation)
        // 縦スクショ + 縦ベゼル選択中: 回転不要の自分自身は除外
        let direct = AspectMatcher.suggestionsAllowingRotation(screenshotWidth: 1179, screenshotHeight: 2556, from: list, excluding: "p")
        #expect(direct.isEmpty)
    }

    @Test func sortsByDifferenceThenPrefersNoRotation() {
        let list = [bezel("far", 1000, 2200), bezel("near", 1179, 2556)]
        let s = AspectMatcher.suggestionsAllowingRotation(screenshotWidth: 1179, screenshotHeight: 2556, from: list, tolerance: 0.2)
        #expect(s.first?.bezel.bezelFile == "near")

        // 正方形ベゼルは回転しても同じ差。回転不要が先
        let sq = AspectMatcher.suggestionsAllowingRotation(screenshotWidth: 100, screenshotHeight: 100, from: [bezel("sq", 50, 50)])
        #expect(sq.map(\.needsRotation) == [false, true])
    }

    @Test func noMatchesGivesEmpty() {
        #expect(AspectMatcher.suggestionsAllowingRotation(screenshotWidth: 300, screenshotHeight: 100,
                                                          from: [bezel("p", 1179, 2556)]).isEmpty)
    }
}
