import Testing
import Foundation
import CoreGraphics
import SwiftUI
@testable import FrameBezelApp

/// 本物の Application Support / UserDefaults に触れないよう、一時フォルダのライブラリと専用の defaults で AppModel を作る。
@MainActor
private struct ModelEnv {
    let root: URL
    let library: BezelLibrary
    let defaults: UserDefaults
    private let cleanDefaults: () -> Void

    /// `bezels` は (ファイル名, 幅, 高さ, 窓) 。ライブラリへ登録してからモデルを作る。
    init(bezels: [(String, Int, Int, CGRect)] = ModelEnv.standard) throws {
        root = try TestSupport.makeTempDirectory()
        library = BezelLibrary(appDirectory: root.appendingPathComponent("app", isDirectory: true))
        (defaults, cleanDefaults) = TestSupport.makeDefaults()
        let src = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        for (name, w, h, screen) in bezels {
            let url = src.appendingPathComponent(name)
            try TestSupport.writeBezelPNG(to: url, width: w, height: h, screen: screen)
            try library.add(pngURL: url, name: nil, meta: BezelNaming.parse(fileName: name, folderName: nil))
        }
    }

    static let standard: [(String, Int, Int, CGRect)] = [
        ("iPhone X - Black - Portrait.png", 100, 200, CGRect(x: 20, y: 20, width: 60, height: 160)),
        ("iPhone X - White - Portrait.png", 100, 200, CGRect(x: 20, y: 20, width: 60, height: 160)),
        ("iPhone X - Black - Landscape.png", 200, 100, CGRect(x: 20, y: 20, width: 160, height: 60)),
        ("iPad Y - Gray - Portrait.png", 150, 200, CGRect(x: 15, y: 20, width: 120, height: 160)),
    ]

    func makeModel() -> AppModel { AppModel(library: library, defaults: defaults) }

    func cleanup() { TestSupport.remove(root); cleanDefaults() }

    func pngData(_ image: CGImage) throws -> Data {
        let url = root.appendingPathComponent("\(UUID().uuidString).png")
        try ImageFile.writePNG(image, to: url)
        return try Data(contentsOf: url)
    }
}

@MainActor
struct AppModelSetupTests {
    @Test func emptyLibraryStartsEmpty() throws {
        let env = try ModelEnv(bezels: []); defer { env.cleanup() }
        let m = env.makeModel()
        #expect(m.bezels.isEmpty && m.selectedBezel == nil && m.preview == nil)
        #expect(m.exportCanvas == nil && m.screenshot == nil && m.modelGroups.isEmpty)
        #expect(m.aspectMatches == nil && m.imageFrame == nil && m.suggestedBezels.isEmpty)
    }

    @Test func loadsBezelsGroupedByModelAndSelectsAnIPhone() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        #expect(m.bezels.count == 4)
        #expect(Set(m.modelGroups.map(\.model)) == ["iPhone X", "iPad Y"])
        #expect(m.selectedBezel?.modelName == "iPhone X") // 先頭（iPad Y）ではなく、iPhone が既定
        #expect(m.selectedGroup?.model == m.selectedBezel?.modelName)
        #expect(m.thumbnails.count == 2) // 機種ごとの代表だけ
    }

    @Test func defaultBackgroundIsTransparent() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        #expect(m.backgroundKind == .transparent)
        #expect(m.settings.background == .transparent)
    }

    @Test func settingsReflectBackgroundKind() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.backgroundKind = .solid
        m.solidColor = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 1)
        guard case .solid(let c) = m.settings.background else { Issue.record("solid expected"); return }
        #expect(abs(c.r - 0.2) < 0.01 && abs(c.g - 0.4) < 0.01 && abs(c.b - 0.6) < 0.01)
        m.backgroundKind = .gradient
        m.gradientAngle = 33
        guard case .gradient(_, _, let angle) = m.settings.background else { Issue.record("gradient expected"); return }
        #expect(angle == 33)
    }

    @Test func backgroundKindShortNames() {
        #expect(BackgroundKind.gradient.shortName == "グラデ")
        #expect(BackgroundKind.solid.shortName == "単色")
        #expect(BackgroundKind.transparent.shortName == "透明")
        #expect(BackgroundKind.allCases.count == 3)
    }

    @Test func colorConversionRoundTrips() {
        let c = RGBAColor(Color(.sRGB, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.5))
        #expect(abs(c.r - 0.25) < 0.01 && abs(c.g - 0.5) < 0.01 && abs(c.b - 0.75) < 0.01 && abs(c.a - 0.5) < 0.01)
    }
}

@MainActor
struct AppModelScreenshotTests {
    private func model(_ env: ModelEnv, selecting group: String = "iPhone X") -> AppModel {
        let m = env.makeModel()
        m.selectModel(m.modelGroups.first { $0.model == group }!)
        return m
    }

    @Test func loadingScreenshotCreatesPreviewAtBezelSize() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 160)), name: "shot")
        #expect(m.screenshotName == "shot")
        #expect(m.screenshot?.width == 60)
        let p = try #require(m.preview)
        #expect(p.width == m.selectedBezel?.imageWidth && p.height == m.selectedBezel?.imageHeight)
        #expect(m.aspectMatches == true && m.suggestedBezels.isEmpty)
    }

    @Test func loadingFromURLUsesFileNameWithoutExtension() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        let url = env.root.appendingPathComponent("My Shot.png")
        try ImageFile.writePNG(TestSupport.solid(60, 160), to: url)
        m.loadScreenshot(url: url)
        #expect(m.screenshotName == "My Shot")
    }

    @Test func invalidScreenshotSetsErrorAndKeepsState() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.loadScreenshot(data: Data("nope".utf8), name: "x")
        #expect(m.errorMessage != nil && m.screenshot == nil && m.preview == nil)
    }

    @Test func landscapeScreenshotSwitchesToLandscapeBezelOfSameModelKeepingColor() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.selectColor("Black")
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(160, 60)), name: "wide")
        #expect(m.selectedBezel?.effectiveOrientation == .landscape)
        #expect(m.selectedBezel?.color == "Black")
        #expect(m.aspectMatches == true)
    }

    @Test func portraitScreenshotKeepsPortraitBezel() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.selectOrientation(.landscape)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 160)), name: "tall")
        #expect(m.selectedBezel?.effectiveOrientation == .portrait)
    }

    @Test func modelWithSingleOrientationIsNotSwitched() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, selecting: "iPad Y")
        let before = m.selectedBezelFile
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(160, 60)), name: "wide")
        #expect(m.selectedBezelFile == before)
        #expect(m.aspectMatches == false)
    }

    @Test func screenshotAspectIsWidthOverHeight() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        #expect(m.screenshotAspect == nil)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 120)), name: "a")
        #expect(m.screenshotAspect == 0.5)
    }

    // MARK: 提案

    @Test func mismatchSuggestsOneBezelPerModelAndOrientation() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, selecting: "iPad Y")
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 160)), name: "tall")
        #expect(m.aspectMatches == false)
        let s = m.suggestedBezels
        // iPhone X: 縦（色違い 2 枚は 1 件に）と、回転すれば合う横
        #expect(s.count == 2)
        #expect(s.map(\.needsRotation) == [false, true])
        #expect(Set(s.map(\.bezel.modelName)) == ["iPhone X"])
    }

    @Test func suggestionPrefersTheCurrentColor() throws {
        let env = try ModelEnv(bezels: ModelEnv.standard + [("iPad Y - Gray - Landscape.png", 200, 150, CGRect(x: 20, y: 15, width: 160, height: 120))])
        defer { env.cleanup() }
        let m = model(env, selecting: "iPhone X")
        m.selectColor("White")
        m.selectModel(m.modelGroups.first { $0.model == "iPad Y" }!)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 160)), name: "t")
        let direct = try #require(m.suggestedBezels.first { !$0.needsRotation })
        #expect(direct.bezel.modelName == "iPhone X")
    }

    @Test func applyingRotationSuggestionRotatesAndSwitchesBezel() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, selecting: "iPad Y")
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 160)), name: "t")
        let rotated = try #require(m.suggestedBezels.first { $0.needsRotation })
        m.apply(rotated)
        #expect(m.rotation.quarterTurns == 1)
        #expect(m.screenshot?.width == 160 && m.screenshot?.height == 60)
        #expect(m.selectedBezel?.effectiveOrientation == .landscape)
        #expect(m.aspectMatches == true)
    }

    @Test func applyingSuggestionForCurrentBezelOnlyResetsCrop() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 160)), name: "t")
        m.setCrop(ScreenCrop(zoom: 2))
        let current = try #require(m.selectedBezel)
        m.apply(AspectMatcher.Suggestion(bezel: current, needsRotation: false))
        #expect(m.crop.zoom == 1)
    }

    // MARK: 機種・向き・色

    @Test func selectingOrientationAndColorKeepsTheOtherChoice() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.selectOrientation(.portrait); m.selectColor("White")
        #expect(m.selectedBezel?.color == "White" && m.selectedBezel?.effectiveOrientation == .portrait)
        m.selectOrientation(.landscape) // 横には White が無いので Black
        #expect(m.selectedBezel?.effectiveOrientation == .landscape && m.selectedBezel?.color == "Black")
        m.selectOrientation(.portrait)
        #expect(m.selectedBezel?.effectiveOrientation == .portrait)
    }

    @Test func selectingModelWithScreenshotPicksBestOrientation() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, selecting: "iPad Y")
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(160, 60)), name: "wide")
        m.selectModel(m.modelGroups.first { $0.model == "iPhone X" }!)
        #expect(m.selectedBezel?.effectiveOrientation == .landscape)
    }

    @Test func selectingModelWithoutScreenshotKeepsCurrentOrientation() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.selectOrientation(.landscape)
        m.selectModel(m.modelGroups.first { $0.model == "iPhone X" }!)
        #expect(m.selectedBezel?.effectiveOrientation == .landscape)
    }

    @Test func colorSelectionWithoutSelectionDoesNothing() throws {
        let env = try ModelEnv(bezels: []); defer { env.cleanup() }
        let m = env.makeModel()
        m.selectColor("White"); m.selectOrientation(.landscape)
        #expect(m.selectedBezelFile == nil)
    }

    // MARK: 回転

    @Test func rotationSwapsScreenshotAndResetsCrop() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.loadScreenshot(data: try env.pngData(TestSupport.quadrants(60, 160)), name: "q")
        m.setCrop(ScreenCrop(zoom: 2))
        m.rotateClockwise()
        #expect(m.rotation.quarterTurns == 1)
        #expect(m.screenshot?.width == 160 && m.screenshot?.height == 60)
        #expect(m.originalScreenshot?.width == 60) // 元画像は変えない
        m.rotateCounterClockwise()
        #expect(m.rotation == .none && m.screenshot?.width == 60)
        m.rotateCounterClockwise()
        #expect(m.rotation.quarterTurns == 3)
    }

    @Test func rotationWithoutScreenshotIsIgnored() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.rotateClockwise()
        #expect(m.rotation == .none && m.screenshot == nil)
    }

    @Test func loadingANewScreenshotResetsRotation() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 160)), name: "a")
        m.rotateClockwise()
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 160)), name: "b")
        #expect(m.rotation == .none)
    }
}

@MainActor
struct AppModelCropTests {
    /// iPad Y（横向きは無い）の窓 120x160 に、横長の 120x80 を読み込んだ状態。収める = 幅いっぱいの 120x80 が縦中央。
    /// 向きの違う機種だと取り込み時に向きが自動で切り替わるので、単一向きの機種を使う。
    private func loaded(_ env: ModelEnv, w: Int = 120, h: Int = 80) throws -> AppModel {
        let m = env.makeModel()
        m.selectModel(m.modelGroups.first { $0.model == "iPad Y" }!)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(w, h)), name: "s")
        // 横長のスクショには、登録の無い横向きを回転して自動で合わせるので、登録どおりの縦向きを選び直す
        m.selectOrientation(.portrait)
        return m
    }

    @Test func initialCropFitsTheScreenshot() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        let f = try #require(m.imageFrame)
        #expect(abs(f.width - 120) < 1e-6 && abs(f.height - 80) < 1e-6)
        #expect(abs(f.minY - 40) < 1e-6) // 窓の縦中央
    }

    @Test func fillThenFitRestoresFrames() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        let fit = try #require(m.imageFrame)
        m.fillScreen()
        let fill = try #require(m.imageFrame)
        #expect(abs(fill.height - 160) < 1e-6 && abs(fill.width - 240) < 1e-6) // 高さが窓を埋め、幅ははみ出す
        m.fitToScreen()
        #expect(m.imageFrame == fit)
    }

    @Test func setCropClampsIntoValidRange() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.setCrop(ScreenCrop(zoom: 100, offsetX: 100, offsetY: 100))
        #expect(m.crop.zoom == ScreenCrop.maxZoom)
        #expect(abs(m.crop.offsetX) < 100)
    }

    @Test func moveCropSnapsAndReportsIt() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.setImageWidth(60) // どの辺も窓の辺と揃っていない状態にする（60x40、縦中央 y=60）
        // 収めた画像の上辺を窓の上辺に近づける: 現在 y=60。2px 手前まで動かす
        var c = m.crop
        c.offsetY = -(60 - 2) / 160.0
        #expect(m.moveCrop(to: c, snapThreshold: 5) == true)
        let snapped = try #require(m.imageFrame)
        #expect(abs(snapped.minY) < 1e-6)
        var far = m.crop; far.offsetY = 0.1
        #expect(m.moveCrop(to: far, snapThreshold: 1) == false)
    }

    @Test func numericWidthKeepsAspectAndCenter() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        let before = try #require(m.imageFrame)
        m.setImageWidth(60)
        let f = try #require(m.imageFrame)
        #expect(abs(f.width - 60) < 1e-6 && abs(f.height - 40) < 1e-6)
        #expect(abs(f.midX - before.midX) < 1e-6 && abs(f.midY - before.midY) < 1e-6)
    }

    @Test func numericHeightScalesWidthToo() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.setImageHeight(40)
        let f = try #require(m.imageFrame)
        #expect(abs(f.height - 40) < 1e-6 && abs(f.width - 60) < 1e-6)
    }

    @Test func numericOriginMovesOnlyTheGivenAxis() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.setImageWidth(60) // 窓幅より小さくして、両軸とも動かせるようにする
        let before = try #require(m.imageFrame)
        m.setImageOrigin(x: 5)
        let f = try #require(m.imageFrame)
        #expect(abs(f.minX - 5) < 1e-6 && abs(f.minY - before.minY) < 1e-6)
        m.setImageOrigin(y: 7)
        let moved = try #require(m.imageFrame)
        #expect(abs(moved.minY - 7) < 1e-6)
    }

    @Test func numericEditsAreClampedToZoomLimits() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.setImageWidth(1_000_000)
        #expect(m.crop.zoom == ScreenCrop.maxZoom)
        m.setImageWidth(0.0001)
        #expect(m.crop.zoom > 0)
    }

    @Test func numericEditsWithoutScreenshotAreIgnored() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.setImageWidth(10); m.setImageHeight(10); m.setImageOrigin(x: 1, y: 1)
        #expect(m.imageFrame == nil)
    }

    @Test func swappingBezelColorKeepsAdjustmentWhenScreenIsSame() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.selectModel(m.modelGroups.first { $0.model == "iPhone X" }!)
        m.selectOrientation(.portrait)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 120)), name: "s")
        #expect(m.selectedBezel?.effectiveOrientation == .portrait)
        m.setImageWidth(30)
        let frame = m.imageFrame
        m.selectColor("White")
        #expect(m.selectedBezel?.color == "White")
        #expect(m.imageFrame == frame)
    }
}

@MainActor
struct AppModelExportTests {
    private func loaded(_ env: ModelEnv, orientation: BezelOrientation = .portrait) throws -> AppModel {
        let m = env.makeModel()
        m.selectModel(m.modelGroups.first { $0.model == "iPhone X" }!)
        m.selectOrientation(orientation)
        let size = orientation == .portrait ? (60, 160) : (160, 60)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(size.0, size.1)), name: "shot")
        return m
    }

    private var phone: AppStoreSize { AppStoreSize.all.first { $0.width == 1320 }! }

    @Test func noExportSizeMeansBezelSize() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        #expect(m.exportSize == nil)
        let c = try #require(m.exportCanvas)
        #expect(c.width == 100 && c.height == 200)
    }

    @Test func exportCanvasFollowsBezelOrientation() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.exportSizeID = phone.id
        #expect(m.exportCanvas?.width == 1320 && m.exportCanvas?.height == 2868)
        m.selectOrientation(.landscape)
        #expect(m.exportCanvas?.width == 2868 && m.exportCanvas?.height == 1320)
    }

    @Test func exportSizeIsPersistedAndRestored() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.exportSizeID = phone.id
        #expect(env.defaults.string(forKey: "exportSizeID") == phone.id)
        #expect(env.makeModel().exportSizeID == phone.id)
        m.exportSizeID = nil
        #expect(env.makeModel().exportSizeID == nil)
    }

    @Test func unknownStoredSizeIDIsIgnored() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        env.defaults.set("gone-1x1", forKey: "exportSizeID")
        let m = env.makeModel()
        #expect(m.exportSize == nil)
    }

    @Test func previewMatchesExportCanvasAspectWhenSizeIsChosen() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.exportSizeID = phone.id
        let p = try #require(m.preview)
        #expect(max(p.width, p.height) <= 2000)
        #expect(abs(Double(p.width) / Double(p.height) - 1320.0 / 2868.0) < 0.002)
    }

    @Test func previewUpdatesWhenSizeOrOrientationChanges() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.exportSizeID = phone.id
        let portrait = try #require(m.preview)
        #expect(portrait.height > portrait.width)
        m.selectOrientation(.landscape)
        let landscape = try #require(m.preview)
        #expect(landscape.width > landscape.height)
        m.exportSizeID = nil
        let plain = try #require(m.preview)
        #expect(plain.width == 200 && plain.height == 100) // ベゼル元サイズ
    }

    @Test func previewWithChosenSizeIsOpaque() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.exportSizeID = phone.id
        let p = try #require(m.preview)
        #expect(TestSupport.pixel(p, 1, 1).a == 255) // 余白は白で埋まる
    }

    @Test func previewWithoutSizeKeepsTransparency() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        #expect(m.preview?.alphaInfo != .noneSkipFirst)
    }

    @Test func suggestedFileNameWithoutSize() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        #expect(m.suggestedFileName == "shot_\(m.selectedBezel!.modelName).png")
        #expect(!m.suggestedFileName.contains("Bezel"))
    }

    @Test func suggestedFileNameWithSizeAddsDimensions() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = try loaded(env)
        m.exportSizeID = phone.id
        #expect(m.suggestedFileName.hasSuffix("_1320x2868.png"))
    }

    @Test func suggestedFileNameIsSanitizedAndHasFallbacks() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.selectModel(m.modelGroups[0])
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 160)), name: "a/b:c")
        #expect(!m.suggestedFileName.contains("/") && !m.suggestedFileName.contains(":"))
        #expect(m.suggestedFileName.hasPrefix("a-b-c_"))
        let empty = try ModelEnv(bezels: []); defer { empty.cleanup() }
        #expect(empty.makeModel().suggestedFileName == "screenshot_bezel.png")
    }
}

@MainActor
struct AppModelLibraryAndPresetTests {
    @Test func addingSinglePNGSelectsItAndOpensEditor() throws {
        let env = try ModelEnv(bezels: []); defer { env.cleanup() }
        let m = env.makeModel()
        let url = env.root.appendingPathComponent("Bezel-New-1.png")
        try TestSupport.writeBezelPNG(to: url)
        m.addBezelOrFolder(urls: [url])
        #expect(m.bezels.count == 1 && m.selectedBezel?.name == "New 1")
        #expect(m.editingBezel?.bezelFile == m.selectedBezelFile)
        #expect(m.thumbnails[m.selectedBezelFile ?? ""] != nil)
    }

    @Test func addingSeveralPNGsDoesNotOpenEditor() throws {
        let env = try ModelEnv(bezels: []); defer { env.cleanup() }
        let m = env.makeModel()
        var urls: [URL] = []
        for n in ["Bezel-A.png", "Bezel-B.png"] {
            let u = env.root.appendingPathComponent(n)
            try TestSupport.writeBezelPNG(to: u)
            urls.append(u)
        }
        m.addBezelOrFolder(urls: urls)
        #expect(m.bezels.count == 2 && m.editingBezel == nil)
    }

    @Test func addingBrokenPNGReportsError() throws {
        let env = try ModelEnv(bezels: []); defer { env.cleanup() }
        let m = env.makeModel()
        let url = env.root.appendingPathComponent("solid.png")
        try ImageFile.writePNG(TestSupport.solid(30, 30), to: url)
        m.addBezel(url: url)
        #expect(m.errorMessage?.contains("追加できません") == true && m.bezels.isEmpty)
    }

    @Test func importingAFolderRunsInBackgroundAndSummarizes() async throws {
        let env = try ModelEnv(bezels: []); defer { env.cleanup() }
        let m = env.makeModel()
        let folder = env.root.appendingPathComponent("Phone Z", isDirectory: true)
        for n in ["Phone Z - Black - Portrait.png", "Phone Z - White - Portrait.png"] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try TestSupport.writeBezelPNG(to: folder.appendingPathComponent(n))
        }
        m.addBezelOrFolder(urls: [folder])
        #expect(m.isImporting)
        for _ in 0..<500 where m.isImporting || m.importSummary == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!m.isImporting)
        #expect(m.bezels.count == 2)
        #expect(m.selectedBezel?.modelName == "Phone Z")
        #expect(m.importSummary?.contains("2 枚のベゼルを追加しました（1 機種）") == true)

        // もう一度取り込むと重複スキップが報告される
        m.importSummary = nil
        m.addBezelOrFolder(urls: [folder])
        for _ in 0..<500 where m.isImporting || m.importSummary == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(m.importSummary?.contains("スキップ: 2 枚") == true)
        #expect(m.bezels.count == 2)
    }

    @Test func importingEmptyFolderMentionsIt() async throws {
        let env = try ModelEnv(bezels: []); defer { env.cleanup() }
        let m = env.makeModel()
        let folder = env.root.appendingPathComponent("Nothing", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        m.addBezelOrFolder(urls: [folder])
        for _ in 0..<500 where m.isImporting || m.importSummary == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(m.importSummary?.contains("Nothing") == true)
        #expect(m.bezels.isEmpty)
    }

    @Test func deletingAModelRemovesAllItsVariantsAndReselects() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        let phone = try #require(m.modelGroups.first { $0.model == "iPhone X" })
        m.selectModel(phone)
        m.deleteModel(phone)
        #expect(m.modelGroups.map(\.model) == ["iPad Y"])
        #expect(m.selectedBezel?.modelName == "iPad Y")
        #expect(m.thumbnails.keys.allSatisfy { k in m.bezels.contains { $0.bezelFile == k } })
        #expect(try env.library.list().count == 1)
    }

    @Test func deletingTheLastModelClearsSelectionAndPreview() throws {
        let env = try ModelEnv(bezels: [ModelEnv.standard[3]]); defer { env.cleanup() }
        let m = env.makeModel()
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(120, 160)), name: "s")
        #expect(m.preview != nil)
        let only = try #require(m.modelGroups.first)
        m.deleteModel(only)
        #expect(m.selectedBezelFile == nil && m.selectedBezel == nil && m.preview == nil)
    }

    @Test func updatingTheSelectedBezelRefreshesPreview() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(60, 160)), name: "s")
        var b = try #require(m.selectedBezel)
        b.name = "Edited"
        m.updateBezel(b)
        #expect(m.selectedBezel?.name == "Edited")
        #expect(try env.library.list().contains { $0.name == "Edited" })
    }

    // MARK: プリセット

    @Test func savingPresetStoresBezelAndBackground() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.backgroundKind = .solid
        m.savePreset(name: "  Dark  ")
        let p = try #require(m.presets.first)
        #expect(p.name == "Dark" && p.bezelFile == m.selectedBezelFile)
        #expect(PresetStore(directory: env.library.appDirectory).load().count == 1)
    }

    @Test func blankPresetNameIsIgnored() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.savePreset(name: "   ")
        #expect(m.presets.isEmpty)
    }

    @Test func savingSameNameOverwrites() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.savePreset(name: "A")
        m.backgroundKind = .gradient
        m.savePreset(name: "A")
        #expect(m.presets.count == 1)
        if case .gradient = m.presets[0].settings.background {} else { Issue.record("overwritten preset should be gradient") }
    }

    @Test func applyingPresetRestoresBackgroundAndBezel() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        let target = try #require(m.bezels.last)
        m.selectedBezelFile = target.bezelFile
        m.backgroundKind = .gradient
        m.gradientAngle = 45
        m.savePreset(name: "G")
        let preset = try #require(m.presets.first)

        m.selectedBezelFile = m.bezels.first?.bezelFile
        m.backgroundKind = .transparent
        m.gradientAngle = 90
        m.apply(preset)
        #expect(m.backgroundKind == .gradient && m.gradientAngle == 45)
        #expect(m.selectedBezelFile == target.bezelFile)
    }

    @Test func applyingSolidAndTransparentPresets() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.apply(Preset(name: "S", bezelFile: nil, settings: ComposeSettings(background: .solid(RGBAColor(r: 1, g: 0, b: 0)))))
        #expect(m.backgroundKind == .solid)
        #expect(RGBAColor(m.solidColor).r > 0.99)
        m.apply(Preset(name: "T", bezelFile: nil, settings: ComposeSettings(background: .transparent)))
        #expect(m.backgroundKind == .transparent)
    }

    @Test func presetWithDeletedBezelKeepsCurrentSelection() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        let current = m.selectedBezelFile
        m.apply(Preset(name: "X", bezelFile: "deleted.png", settings: ComposeSettings(background: .transparent)))
        #expect(m.selectedBezelFile == current)
    }

    @Test func deletingPreset() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.savePreset(name: "A"); m.savePreset(name: "B")
        let first = try #require(m.presets.first)
        m.deletePreset(first)
        #expect(m.presets.map(\.name) == ["B"])
    }

    @Test func presetsPersistAcrossModels() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        env.makeModel().savePreset(name: "Keep")
        #expect(env.makeModel().presets.map(\.name) == ["Keep"])
    }

    @Test func bezelImageForBezelLoadsFromLibrary() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        let bezel = try #require(m.selectedBezel)
        let image = try #require(m.bezelImage(for: bezel))
        #expect(image.width > 0)
    }
}

@MainActor
struct AppModelCategoryTests {
    private let mixed: [(String, Int, Int, CGRect)] = ModelEnv.standard + [
        ("MacBook Neo - Blush.png", 200, 100, CGRect(x: 20, y: 20, width: 160, height: 60)),
        ("Apple Watch Ultra 4 - Natural + Trail Loop Sand.png", 100, 120, CGRect(x: 20, y: 20, width: 60, height: 80)),
    ]

    @Test func categoriesListOnlyWhatIsImported() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        #expect(env.makeModel().categories == [.iPhone, .iPad])
        let all = try ModelEnv(bezels: mixed); defer { all.cleanup() }
        #expect(all.makeModel().categories == [.iPhone, .iPad, .mac, .watch])
    }

    @Test func listShowsOnlyModelsOfTheBrowsingCategory() throws {
        let env = try ModelEnv(bezels: mixed); defer { env.cleanup() }
        let m = env.makeModel()
        m.showCategory(.iPad)
        #expect(m.visibleGroups.map(\.model) == ["iPad Y"])
        m.showCategory(.mac)
        #expect(m.visibleGroups.map(\.model) == ["MacBook Neo"])
        m.showCategory(.watch)
        #expect(m.visibleGroups.map(\.model) == ["Apple Watch Ultra 4"])
        m.showCategory(.iPhone)
        #expect(m.visibleGroups.map(\.model) == ["iPhone X"])
    }

    @Test func selectingAModelSwitchesTheCategoryAutomatically() throws {
        let env = try ModelEnv(bezels: mixed); defer { env.cleanup() }
        let m = env.makeModel()
        let neo = try #require(m.modelGroups.first { $0.model == "MacBook Neo" })
        m.selectModel(neo)
        #expect(m.browsingCategory == .mac)
        let watch = try #require(m.modelGroups.first { $0.model == "Apple Watch Ultra 4" })
        m.selectModel(watch)
        #expect(m.browsingCategory == .watch)
    }

    @Test func initialCategoryFollowsTheSelectedBezel() throws {
        let env = try ModelEnv(bezels: [mixed[3], mixed[4]]); defer { env.cleanup() } // iPad Y と MacBook Neo だけ
        let m = env.makeModel()
        #expect(m.browsingCategory == DeviceCategory.of(modelName: m.selectedBezel!.modelName))
        #expect(m.visibleGroups.contains { $0.model == m.selectedBezel!.modelName })
    }

    @Test func browsingAnotherCategoryKeepsTheSelection() throws {
        let env = try ModelEnv(bezels: mixed); defer { env.cleanup() }
        let m = env.makeModel()
        m.selectModel(try #require(m.modelGroups.first { $0.model == "iPhone X" }))
        let selected = m.selectedBezelFile
        m.showCategory(.mac)
        #expect(m.selectedBezelFile == selected)
    }

    @Test func deletingTheLastModelOfACategoryMovesToAnExistingOne() throws {
        let env = try ModelEnv(bezels: mixed); defer { env.cleanup() }
        let m = env.makeModel()
        m.showCategory(.watch)
        m.deleteModel(try #require(m.modelGroups.first { $0.model == "Apple Watch Ultra 4" }))
        #expect(!m.categories.contains(.watch))
        #expect(m.categories.contains(m.browsingCategory))
    }

    @Test func importedFolderSwitchesToItsCategory() async throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        let folder = env.root.appendingPathComponent("Mac/MacBook Neo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try TestSupport.writeBezelPNG(to: folder.appendingPathComponent("MacBook Neo - Blush.png"), width: 200, height: 100,
                                      screen: CGRect(x: 20, y: 20, width: 160, height: 60))
        m.addBezelOrFolder(urls: [folder])
        for _ in 0..<500 where m.isImporting || m.importSummary == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(m.categories.contains(.mac))
        #expect(m.browsingCategory == .mac)
        #expect(m.selectedBezel?.modelName == "MacBook Neo")
    }
}

@MainActor
struct AppModelVariantTests {
    /// Duo 相当: 内側（縦・横）、外側・閉じる（縦・横）、外側・開く（1 種類）。色は Night Sky / Star White。
    private func duoEnv() throws -> ModelEnv {
        var list: [(String, Int, Int, CGRect)] = []
        for color in ["Night Sky", "Star White"] {
            list += [
                ("iPhone Duo - \(color) - Inner Open Portrait.png", 100, 130, CGRect(x: 10, y: 10, width: 80, height: 110)),
                ("iPhone Duo - \(color) - Inner Open Landscape.png", 130, 100, CGRect(x: 10, y: 10, width: 110, height: 80)),
                ("iPhone Duo - \(color) - Outer Closed Portrait.png", 80, 120, CGRect(x: 10, y: 10, width: 60, height: 100)),
                ("iPhone Duo - \(color) - Outer Closed Landscape.png", 120, 80, CGRect(x: 10, y: 10, width: 100, height: 60)),
                ("iPhone Duo - \(color) - Outer Open.png", 200, 120, CGRect(x: 110, y: 10, width: 80, height: 100)),
            ]
        }
        return try ModelEnv(bezels: list)
    }

    @Test func selectingAVariantKeepsOrientationAndColor() throws {
        let env = try duoEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.selectModel(m.modelGroups[0])
        m.selectOrientation(.landscape); m.selectColor("Star White")
        m.selectVariant("Outer Closed")
        #expect(m.selectedBezel?.variant == "Outer Closed")
        #expect(m.selectedBezel?.effectiveOrientation == .landscape && m.selectedBezel?.color == "Star White")
    }

    @Test func variantWithASingleOrientationFallsBackToIt() throws {
        let env = try duoEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.selectModel(m.modelGroups[0])
        m.selectVariant("Outer Open")
        #expect(m.selectedBezel?.variant == "Outer Open")
        #expect(m.selectedGroup?.orientations(variant: "Outer Open").count == 1)
    }

    @Test func orientationAndColorChangesStayInTheCurrentVariant() throws {
        let env = try duoEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.selectModel(m.modelGroups[0])
        m.selectVariant("Outer Closed")
        m.selectOrientation(.landscape)
        #expect(m.selectedBezel?.variant == "Outer Closed")
        m.selectColor("Night Sky")
        #expect(m.selectedBezel?.variant == "Outer Closed" && m.selectedBezel?.effectiveOrientation == .landscape)
    }

    @Test func screenshotAspectPicksOrientationWithinTheVariant() throws {
        let env = try duoEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.selectModel(m.modelGroups[0])
        m.selectVariant("Outer Closed")
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(100, 60)), name: "wide")
        #expect(m.selectedBezel?.variant == "Outer Closed" && m.selectedBezel?.effectiveOrientation == .landscape)
    }

    @Test func tileRepresentativeIsTheFirstVariantsPortrait() throws {
        let env = try duoEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        #expect(m.modelGroups.count == 1)
        #expect(m.modelGroups[0].representative.variant == "Inner Open")
    }

    @Test func selectingAVariantWithoutSelectionDoesNothing() throws {
        let env = try ModelEnv(bezels: []); defer { env.cleanup() }
        let m = env.makeModel()
        m.selectVariant("Inner Open")
        #expect(m.selectedBezelFile == nil)
    }
}

@MainActor
struct AppModelInitialSelectionTests {
    @Test func initialSelectionIsTheFirstModelsDefaultForm() throws {
        // 同じ機種に複数の形態があっても、起動時の選択は並び順に左右されず、先頭の形態の縦向きになる
        var list: [(String, Int, Int, CGRect)] = []
        for (n, w, h, r) in [
            ("iPhone Duo - Night Sky - Outer Open.png", 200, 120, CGRect(x: 110, y: 10, width: 80, height: 100)),
            ("iPhone Duo - Night Sky - Outer Closed Portrait.png", 80, 120, CGRect(x: 10, y: 10, width: 60, height: 100)),
            ("iPhone Duo - Night Sky - Inner Open Portrait.png", 100, 130, CGRect(x: 10, y: 10, width: 80, height: 110)),
        ] { list.append((n, w, h, r)) }
        let env = try ModelEnv(bezels: list); defer { env.cleanup() }
        let m = env.makeModel()
        #expect(m.selectedBezel?.variant == "Inner Open" && m.selectedBezel?.effectiveOrientation == .portrait)
    }
}

@MainActor
struct AppModelRotatedBezelTests {
    /// 縦だけ登録の機種（iPad Y）と、縦横ともある機種（iPhone X）
    private func model(_ env: ModelEnv, _ name: String) -> AppModel {
        let m = env.makeModel()
        m.selectModel(m.modelGroups.first { $0.model == name }!)
        return m
    }

    @Test func choosingAMissingOrientationRotatesTheRegisteredBezel() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, "iPad Y")
        #expect(!m.isBezelTurned && m.selectedBezel?.imageWidth == 150)
        m.selectOrientation(.landscape)
        #expect(m.isBezelTurned)
        #expect(m.selectedBezel?.effectiveOrientation == .landscape)
        #expect(m.selectedBezel?.imageWidth == 200 && m.selectedBezel?.imageHeight == 150) // 回した寸法
        #expect(m.selectedRegisteredBezel?.imageWidth == 150) // 保存データは回さない
        #expect(m.selectedRegisteredBezel?.effectiveOrientation == .portrait)
        m.selectOrientation(.portrait)
        #expect(!m.isBezelTurned && m.selectedBezel == m.selectedRegisteredBezel)
    }

    @Test func registeredOrientationIsNeverRotated() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, "iPhone X")
        m.selectOrientation(.landscape)
        #expect(!m.isBezelTurned && m.selectedBezel?.imageWidth == 200)
    }

    @Test func rotatedBezelProducesRotatedPreviewAndScreenArea() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, "iPad Y")
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(160, 120)), name: "wide") // 4:3 の横長 → 回転が合う
        #expect(m.isBezelTurned && m.aspectMatches == true)
        let p = try #require(m.preview)
        #expect(p.width == 200 && p.height == 150)
        // 回した窓（x=20,y=15,160x120）の中央にスクショ、外側はベゼル（黒）
        #expect(TestSupport.pixel(p, 100, 75) == .init(r: 255, g: 0, b: 0, a: 255))
        #expect(TestSupport.pixel(p, 5, 75).r == 0 && TestSupport.pixel(p, 5, 75).a == 255)
    }

    @Test func landscapeScreenshotAutoRotatesAPortraitOnlyModel() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, "iPad Y")
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(160, 120)), name: "w")
        #expect(m.isBezelTurned && m.selectedBezel?.effectiveOrientation == .landscape)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(120, 160)), name: "t")
        #expect(!m.isBezelTurned && m.selectedBezel?.effectiveOrientation == .portrait)
    }

    @Test func changingColorKeepsTheRotation() throws {
        let env = try ModelEnv(bezels: [ModelEnv.standard[3], ("iPad Y - Pink - Portrait.png", 150, 200, CGRect(x: 15, y: 20, width: 120, height: 160))])
        defer { env.cleanup() }
        let m = model(env, "iPad Y")
        m.selectOrientation(.landscape)
        m.selectColor("Pink")
        #expect(m.isBezelTurned && m.selectedBezel?.color == "Pink" && m.selectedBezel?.effectiveOrientation == .landscape)
    }

    @Test func selectingAnotherBezelResetsTheRotation() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, "iPad Y")
        m.selectOrientation(.landscape)
        #expect(m.isBezelTurned)
        m.selectModel(m.modelGroups.first { $0.model == "iPhone X" }!)
        #expect(!m.isBezelTurned)
    }

    @Test func exportUsesTheRotatedBezel() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, "iPad Y")
        m.selectOrientation(.landscape)
        let c = try #require(m.exportCanvas)
        #expect(c.width == 200 && c.height == 150) // 回した寸法がそのまま書き出しサイズになる
        let phone = AppStoreSize.all.first { $0.family == .iPad && $0.width == 2064 }!
        m.exportSizeID = phone.id
        #expect(m.exportCanvas?.width == 2752 && m.exportCanvas?.height == 2064) // 回転した向きで横長のサイズ
    }

    @Test func editingAlwaysTargetsTheRegisteredBezel() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, "iPad Y")
        m.selectOrientation(.landscape)
        var edited = try #require(m.selectedRegisteredBezel)
        edited.aperture.x += 1
        m.updateBezel(edited)
        #expect(try env.library.list().first { $0.bezelFile == edited.bezelFile }?.imageWidth == 150) // 回した寸法が保存されない
        #expect(m.isBezelTurned && m.selectedBezel?.effectiveOrientation == .landscape)
    }

    @Test func numericAndCropEditsWorkOnTheRotatedScreen() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, "iPad Y")
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(160, 120)), name: "w")
        #expect(m.isBezelTurned)
        let f = try #require(m.imageFrame)
        #expect(abs(f.width - 160) < 1e-6 && abs(f.height - 120) < 1e-6) // 回した窓にちょうど収まる
        m.setImageWidth(80)
        #expect(abs(try #require(m.imageFrame).width - 80) < 1e-6)
    }

    @Test func screenAreaSurvivesBezelColorSwapButResetsOnOrientationChange() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env, "iPad Y")
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(160, 120)), name: "w")
        m.setImageWidth(80)
        let small = m.imageFrame
        m.selectOrientation(.portrait) // 窓の寸法が変わる → 収めるに戻る
        #expect(m.imageFrame != small)
    }
}

@MainActor
struct AppModelFixedOrientationTests {
    private let mac: (String, Int, Int, CGRect) = ("MacBook Neo - Blush.png", 200, 120, CGRect(x: 20, y: 20, width: 160, height: 80))

    @Test func portraitScreenshotDoesNotRotateAMac() throws {
        let env = try ModelEnv(bezels: [mac]); defer { env.cleanup() }
        let m = env.makeModel()
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(80, 160)), name: "tall")
        #expect(!m.isBezelTurned && m.selectedBezel?.effectiveOrientation == .landscape)
        #expect(m.selectedBezel?.imageWidth == 200)
    }

    @Test func selectingAnOrientationOnAMacChangesNothing() throws {
        let env = try ModelEnv(bezels: [mac]); defer { env.cleanup() }
        let m = env.makeModel()
        m.selectOrientation(.portrait)
        #expect(!m.isBezelTurned && m.selectedBezel?.effectiveOrientation == .landscape)
    }

    @Test func orientationChoicesAreHiddenForMacAndWatchButNotForPhones() throws {
        let watch: (String, Int, Int, CGRect) = ("Apple Watch Ultra 4 - Natural + Trail Loop Sand.png", 100, 120, CGRect(x: 20, y: 20, width: 60, height: 80))
        let env = try ModelEnv(bezels: ModelEnv.standard + [mac, watch]); defer { env.cleanup() }
        let m = env.makeModel()
        func choices(_ name: String) -> Int { m.modelGroups.first { $0.model == name }!.selectableOrientations().count }
        #expect(choices("MacBook Neo") == 1)
        #expect(choices("Apple Watch Ultra 4") == 1)
        #expect(choices("iPhone X") == 2 && choices("iPad Y") == 2)
    }
}

@MainActor
struct AppModelOrderTests {
    @Test func categoryListShowsNewestFirst() throws {
        let bezels: [(String, Int, Int, CGRect)] = [
            ("iPhone 11 - Portrait.png", 100, 200, CGRect(x: 20, y: 20, width: 60, height: 160)),
            ("iPhone 17 - Black - Portrait.png", 100, 200, CGRect(x: 20, y: 20, width: 60, height: 160)),
            ("iPhone 13 - Midnight.png", 100, 200, CGRect(x: 20, y: 20, width: 60, height: 160)),
            ("iPhone 17 Pro - Silver - Portrait.png", 100, 200, CGRect(x: 20, y: 20, width: 60, height: 160)),
        ]
        let env = try ModelEnv(bezels: bezels); defer { env.cleanup() }
        let m = env.makeModel()
        m.showCategory(.iPhone)
        #expect(m.visibleGroups.map(\.model) == ["iPhone 17 Pro", "iPhone 17", "iPhone 13", "iPhone 11"])
    }

    @Test func otherCategoriesAreNotMixedIn() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = env.makeModel()
        m.showCategory(.iPad)
        #expect(m.visibleGroups.map(\.model) == ["iPad Y"])
    }
}

@MainActor
struct AppModelDefaultSelectionTests {
    private let phone = CGRect(x: 20, y: 20, width: 60, height: 160)

    private func make(_ names: [String]) throws -> ModelEnv {
        try ModelEnv(bezels: names.map { ($0, 100, 200, phone) })
    }

    @Test func startsOnTheNewestIPhoneEvenWhenOtherDevicesSortFirst() throws {
        // 名前順では Apple Watch や iPad が先頭になるが、既定は iPhone の最新機種
        let env = try make(["Apple Watch Ultra 4 - Natural + Trail Loop Sand.png", "iPad Y - Gray - Portrait.png",
                            "iPhone 16 - Black - Portrait.png", "iPhone 17 Pro - Silver - Portrait.png", "iPhone 17 - Black - Portrait.png",
                            "MacBook Neo - Blush.png"])
        defer { env.cleanup() }
        let m = env.makeModel()
        #expect(m.selectedBezel?.modelName == "iPhone 17 Pro")
        #expect(m.browsingCategory == .iPhone)
        #expect(m.visibleGroups.first?.model == "iPhone 17 Pro") // 一覧の先頭と、選択が一致する
    }

    @Test func defaultCategoryIsIPhone() throws {
        #expect(AppModel.defaultCategory == .iPhone)
        let env = try ModelEnv(bezels: []); defer { env.cleanup() }
        #expect(env.makeModel().browsingCategory == .iPhone)
    }

    @Test func fallsBackToTheFirstModelWhenThereIsNoIPhone() throws {
        let env = try make(["MacBook Neo - Blush.png", "iPad Y - Gray - Portrait.png"]); defer { env.cleanup() }
        let m = env.makeModel()
        #expect(m.selectedBezel != nil)
        #expect(m.selectedBezel?.modelName == m.modelGroups.first?.model)
        #expect(m.categories.contains(m.browsingCategory)) // 表示中の種類は、あるものになる
    }

    @Test func startsInPortraitOfTheDefaultModel() throws {
        let env = try ModelEnv(bezels: [("iPhone 17 - Black - Landscape.png", 200, 100, CGRect(x: 20, y: 20, width: 160, height: 60)),
                                        ("iPhone 17 - Black - Portrait.png", 100, 200, phone)])
        defer { env.cleanup() }
        #expect(env.makeModel().selectedBezel?.effectiveOrientation == .portrait)
    }

    @Test func deletingTheSelectedIPhoneSelectsTheNextNewestIPhone() throws {
        let env = try make(["iPhone 16 - Black - Portrait.png", "iPhone 17 - Black - Portrait.png", "iPad Y - Gray - Portrait.png"])
        defer { env.cleanup() }
        let m = env.makeModel()
        #expect(m.selectedBezel?.modelName == "iPhone 17")
        m.deleteModel(try #require(m.modelGroups.first { $0.model == "iPhone 17" }))
        #expect(m.selectedBezel?.modelName == "iPhone 16")
    }
}

@MainActor
struct AppModelAspectBannerTests {
    /// iPad Y（縦のみ・窓 120x160、3:4）。比が大きく外れるスクショ（正方形に近い 100x100）は不一致になる
    private func model(_ env: ModelEnv) -> AppModel {
        let m = env.makeModel()
        m.selectModel(m.modelGroups.first { $0.model == "iPad Y" }!)
        return m
    }
    private func mismatch(_ env: ModelEnv, name: String = "m") throws -> Data { try env.pngData(TestSupport.solid(100, 100)) }
    private func match(_ env: ModelEnv) throws -> Data { try env.pngData(TestSupport.solid(60, 80)) }

    @Test func bannerShowsOnlyForAMismatch() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        #expect(!m.showsAspectBanner) // スクショ未読込
        m.loadScreenshot(data: try match(env), name: "ok")
        #expect(m.aspectMatches == true && !m.showsAspectBanner)
        m.loadScreenshot(data: try mismatch(env), name: "ng")
        #expect(m.aspectMatches == false && m.showsAspectBanner)
    }

    @Test func dismissingHidesTheBanner() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.loadScreenshot(data: try mismatch(env), name: "ng")
        m.dismissAspectBanner()
        #expect(m.isAspectBannerDismissed && !m.showsAspectBanner)
        #expect(m.aspectMatches == false) // 不一致そのものは変わらない（切り抜きボタンなどの動作に影響しない）
    }

    @Test func loadingANewScreenshotShowsTheBannerAgain() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.loadScreenshot(data: try mismatch(env), name: "a")
        m.dismissAspectBanner()
        m.loadScreenshot(data: try mismatch(env), name: "b")
        #expect(!m.isAspectBannerDismissed && m.showsAspectBanner)
    }

    @Test func reloadingTheSameFileAlsoCountsAsANewImage() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        let url = env.root.appendingPathComponent("s.png")
        try ImageFile.writePNG(TestSupport.solid(100, 100), to: url)
        m.loadScreenshot(url: url)
        m.dismissAspectBanner()
        m.loadScreenshot(url: url)
        #expect(m.showsAspectBanner)
    }

    @Test func dismissalDoesNotCarryOverToAMatchingThenMismatchingImage() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.loadScreenshot(data: try mismatch(env), name: "a")
        m.dismissAspectBanner()
        m.loadScreenshot(data: try match(env), name: "ok")
        #expect(!m.showsAspectBanner && !m.isAspectBannerDismissed)
        m.loadScreenshot(data: try mismatch(env), name: "b")
        #expect(m.showsAspectBanner)
    }

    @Test func rotatingOrSwitchingBezelsDoesNotBringTheBannerBack() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.loadScreenshot(data: try env.pngData(TestSupport.solid(100, 40)), name: "wide") // どの向きでも不一致
        m.dismissAspectBanner()
        m.rotateClockwise()
        #expect(!m.showsAspectBanner)
        m.selectModel(m.modelGroups.first { $0.model == "iPhone X" }!)
        #expect(!m.showsAspectBanner)
    }

    @Test func dismissingBeforeAnyMismatchIsHarmless() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.dismissAspectBanner()
        m.loadScreenshot(data: try mismatch(env), name: "a") // 新しい画像なので、また出る
        #expect(m.showsAspectBanner)
    }

    @Test func aFailedLoadKeepsTheBannerState() throws {
        let env = try ModelEnv(); defer { env.cleanup() }
        let m = model(env)
        m.loadScreenshot(data: try mismatch(env), name: "a")
        m.dismissAspectBanner()
        m.loadScreenshot(data: Data("broken".utf8), name: "x") // 読み込めない画像では、画像は変わらない
        #expect(!m.showsAspectBanner)
    }
}
