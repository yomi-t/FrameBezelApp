import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import FrameBezelApp

struct BezelNamingTests {
    @Test func parsesAppleFileName() {
        let m = BezelNaming.parse(fileName: "iPhone 18 Pro - Black - Landscape.png", folderName: "iPhone 18 Pro")
        #expect(m.model == "iPhone 18 Pro")
        #expect(m.color == "Black")
        #expect(m.orientation == .landscape)
    }

    @Test func multiWordColorAndCaseInsensitiveOrientation() {
        let m = BezelNaming.parse(fileName: "iPhone 18 Pro - Cosmic Orange - portrait.png", folderName: "iPhone 18 Pro")
        #expect(m.color == "Cosmic Orange")
        #expect(m.orientation == .portrait)
    }

    @Test func noColorMeansNil() {
        let m = BezelNaming.parse(fileName: "iPad Pro - Portrait.png", folderName: "iPad Pro")
        #expect(m.color == nil)
        #expect(m.model == "iPad Pro")
    }

    @Test func singleFileWithoutFolderFallsBackToModelFromName() {
        let m = BezelNaming.parse(fileName: "iPhone 18 - White - Portrait.png", folderName: nil)
        #expect(m.model == "iPhone 18")
        #expect(m.color == "White")
    }

    @Test func legacyNameIsNotTreatedAsModel() {
        let m = BezelNaming.parse(fileName: "Bezel-iPhone-17.png", folderName: nil)
        #expect(m.model == nil)
    }
}

struct BezelGroupTests {
    private func bezel(_ model: String, _ o: BezelOrientation, _ color: String?) -> Bezel {
        Bezel(name: model, bezelFile: "\(model)-\(color ?? "x")-\(o).png", imageWidth: 10, imageHeight: 10,
              aperture: Aperture(x: 0, y: 0, width: 1, height: 1, cornerRadius: 0),
              model: model, orientation: o, color: color)
    }

    @Test func groupsAndPicks() {
        let list = [bezel("A", .portrait, "Black"), bezel("A", .portrait, "White"),
                    bezel("A", .landscape, "Black"), bezel("B", .portrait, nil)]
        let groups = BezelCatalog.groups(list)
        #expect(groups.map(\.model) == ["A", "B"])
        let a = groups[0]
        #expect(a.orientations == [.portrait, .landscape])
        #expect(a.colors(for: .portrait) == ["Black", "White"])
        #expect(a.colors(for: .landscape) == ["Black"])
        // 向きを変えても色を引き継ぐ。無い色なら同じ向きの先頭にフォールバック
        #expect(a.pick(orientation: .landscape, color: "White").color == "Black")
        #expect(a.pick(orientation: .portrait, color: "White").color == "White")
    }
}

struct BezelOrientationDefaultTests {
    private func bezel(_ o: BezelOrientation, w: Double, h: Double, color: String) -> Bezel {
        Bezel(name: "A", bezelFile: "A-\(color)-\(o).png", imageWidth: 10, imageHeight: 10,
              aperture: Aperture(x: 0, y: 0, width: w, height: h, cornerRadius: 0),
              model: "A", orientation: o, color: color)
    }

    @Test func picksOrientationByScreenshotAspect() {
        let group = BezelCatalog.groups([
            bezel(.portrait, w: 1179, h: 2556, color: "Black"),
            bezel(.landscape, w: 2556, h: 1179, color: "Black"),
            bezel(.landscape, w: 2556, h: 1179, color: "White"),
        ])[0]
        let landscape = group.bestMatch(screenshotWidth: 2556, screenshotHeight: 1179, color: "White")
        #expect(landscape.effectiveOrientation == .landscape)
        #expect(landscape.color == "White")
        let portrait = group.bestMatch(screenshotWidth: 1179, screenshotHeight: 2556, color: "Black")
        #expect(portrait.effectiveOrientation == .portrait)
    }
}

struct BezelImportTests {
    /// 透明な窓つきの擬似ベゼル PNG を作る。
    private func writeBezel(to url: URL) throws {
        let w = 100, h = 200
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.clear(CGRect(x: 20, y: 20, width: 60, height: 160))
        try ImageFile.writePNG(ctx.makeImage()!, to: url)
    }

    @Test func importsFolderAndSortsByModelColorOrientation() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let folder = tmp.appendingPathComponent("src/iPhone 18 Pro", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["iPhone 18 Pro - Black - Portrait.png", "iPhone 18 Pro - Black - Landscape.png",
                     "iPhone 18 Pro - Silver - Portrait.png"] {
            try writeBezel(to: folder.appendingPathComponent(name))
        }
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let library = BezelLibrary(appDirectory: tmp.appendingPathComponent("app"))
        let first = library.importFolder(folder)
        #expect(first.added.count == 3)
        #expect(first.failed.isEmpty)
        let group = try #require(BezelCatalog.groups(try library.list()).first)
        #expect(group.model == "iPhone 18 Pro")
        #expect(group.colors(for: .portrait).sorted() == ["Black", "Silver"])
        #expect(group.orientations == [.portrait, .landscape])

        // 同じフォルダを再取り込みしても増えない
        let second = library.importFolder(folder)
        #expect(second.added.isEmpty)
        #expect(second.skippedDuplicates == 3)
    }
}

struct ScreenCropTests {
    // 画像 200x100（横長）を 100x200 の画面領域へ。埋める=zoom 1、収める=全体が入る最小 zoom
    private func clamp(_ c: ScreenCrop) -> ScreenCrop {
        c.clamped(screenshotWidth: 200, screenshotHeight: 100, screenWidth: 100, screenHeight: 200)
    }

    @Test func fitShrinksBelowFillAndMovesWithinScreen() {
        let fit = clamp(.fit)
        #expect(fit.zoom < 1)
        // 画像（100x50）は画面領域（100x200）より低いので、縦には余白の範囲（±0.375）まで動かせる。横は動かせない
        let moved = clamp(ScreenCrop(zoom: 0, offsetX: 0.5, offsetY: 0.5))
        #expect(moved.offsetX == 0)
        #expect(abs(moved.offsetY - 0.375) < 1e-9)
    }

    @Test func resizeKeepsAnchorCornerFixed() {
        let a = Aperture(x: 10, y: 20, width: 100, height: 200, cornerRadius: 0)
        let start = ScreenCrop(zoom: 1, offsetX: 0.1, offsetY: -0.05)
        let before = start.imageRect(screenshotWidth: 200, screenshotHeight: 100, aperture: a)
        let anchor = CGPoint(x: before.minX, y: before.minY)
        let after = start.resized(by: 1.5, anchor: anchor, screenshotWidth: 200, screenshotHeight: 100, aperture: a)
            .imageRect(screenshotWidth: 200, screenshotHeight: 100, aperture: a)
        #expect(abs(after.minX - anchor.x) < 1e-6 && abs(after.minY - anchor.y) < 1e-6)
        #expect(abs(after.width / before.width - 1.5) < 1e-6)
    }

    @Test func resizeStopsAtZoomLimits() {
        let a = Aperture(x: 0, y: 0, width: 100, height: 200, cornerRadius: 0)
        let big = ScreenCrop.fill.resized(by: 100, anchor: .zero, screenshotWidth: 200, screenshotHeight: 100, aperture: a)
        #expect(big.zoom == ScreenCrop.maxZoom)
        let small = ScreenCrop.fill.resized(by: 0.0001, anchor: .zero, screenshotWidth: 200, screenshotHeight: 100, aperture: a)
        #expect(abs(small.zoom - 0.25 * ScreenCrop.minScaleOfFit) < 1e-12) // 収まる大きさ（0.25）の 10%
    }

    @Test func fillCanMoveAlongOverflowingAxisOnly() {
        let c = clamp(ScreenCrop(zoom: 1, offsetX: 5, offsetY: 5))
        #expect(c.offsetX > 0)
        #expect(c.offsetY == 0)
    }

    @Test func canShrinkBelowFit() {
        let c = clamp(ScreenCrop(zoom: 0.1)) // fit は 0.25 だが、それより小さくできる
        #expect(abs(c.zoom - 0.1) < 1e-12)
    }

    @Test func matchingAspectHasNoShrink() {
        let c = ScreenCrop.fit.clamped(screenshotWidth: 100, screenshotHeight: 200, screenWidth: 50, screenHeight: 100)
        #expect(c.zoom == 1)
    }
}

struct SnapTests {
    private let a = Aperture(x: 10, y: 20, width: 100, height: 200, cornerRadius: 0)

    @Test func moveSnapsEdgeToFrameEdge() {
        // 画像 100x100 を 100x200 の画面領域に置く。上端が 3px ずれた位置（しきい値 5px 以内）
        // zoom 0.5 で画像は 100x100（幅は画面領域とぴったり）。上端を画面領域の上端から 3px 下にずらす
        let fit = ScreenCrop(zoom: 0.5, offsetX: 0, offsetY: (3.0 - 50.0) / 200)
        let r = fit.imageRect(screenshotWidth: 100, screenshotHeight: 100, aperture: a)
        #expect(abs(r.minY - (a.y + 3)) < 1e-9)
        let snapped = fit.snappedPosition(screenshotWidth: 100, screenshotHeight: 100, aperture: a, threshold: 5)
        #expect(snapped.snapped)
        let after = snapped.crop.imageRect(screenshotWidth: 100, screenshotHeight: 100, aperture: a)
        #expect(abs(after.minY - a.y) < 1e-9)
    }

    @Test func moveDoesNotSnapWhenFar() {
        let c = ScreenCrop(zoom: 0.5, offsetX: 0.3, offsetY: -0.3) // 縦横とも辺から 10px 以上離れている
        #expect(!c.snappedPosition(screenshotWidth: 100, screenshotHeight: 100, aperture: a, threshold: 5).snapped)
    }

    @Test func resizeSnapsWidthToFrameWidth() {
        // 画像 100x100、zoom 0.45 → 幅 90。角を動かして幅が 98（しきい値 5 以内）になる倍率は、幅 100 へ吸着する
        let start = ScreenCrop(zoom: 0.45)
        let rect = start.imageRect(screenshotWidth: 100, screenshotHeight: 100, aperture: a)
        let anchor = CGPoint(x: rect.minX, y: rect.minY)
        let moved = CGPoint(x: rect.maxX, y: rect.maxY)
        let snap = ScreenCrop.snapFactor(98.0 / 90.0, moved: moved, anchor: anchor, aperture: a, threshold: 5)
        #expect(snap.snapped)
        #expect(abs(snap.factor * rect.width - a.width) < 1e-9)
        #expect(!ScreenCrop.snapFactor(0.5, moved: moved, anchor: anchor, aperture: a, threshold: 5).snapped)
    }
}

struct NumericEditTests {
    private let a = Aperture(x: 10, y: 20, width: 100, height: 200, cornerRadius: 0)

    @Test func widthKeepsCenterAndAspect() {
        let start = ScreenCrop(zoom: 0.5, offsetX: 0.1, offsetY: -0.1)
        let before = start.imageRect(screenshotWidth: 100, screenshotHeight: 100, aperture: a)
        let after = start.withImageWidth(60, screenshotWidth: 100, screenshotHeight: 100, aperture: a)
            .imageRect(screenshotWidth: 100, screenshotHeight: 100, aperture: a)
        #expect(abs(after.width - 60) < 1e-9 && abs(after.height - 60) < 1e-9)
        #expect(abs(after.midX - before.midX) < 1e-9 && abs(after.midY - before.midY) < 1e-9)
    }

    @Test func originIsRelativeToScreenTopLeft() {
        let moved = ScreenCrop(zoom: 0.5).withImageOrigin(x: 7, y: 30, screenshotWidth: 100, screenshotHeight: 100, aperture: a)
        let r = moved.imageRect(screenshotWidth: 100, screenshotHeight: 100, aperture: a)
        #expect(abs(r.minX - (a.x + 7)) < 1e-9 && abs(r.minY - (a.y + 30)) < 1e-9)
        #expect(moved.zoom == 0.5)
    }
}

struct AppStoreExportTests {
    private func solid(_ w: Int, _ h: Int, alpha: Bool) -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    private let bezel = Bezel(name: "T", bezelFile: "t.png", imageWidth: 100, imageHeight: 200,
                              aperture: Aperture(x: 10, y: 10, width: 80, height: 180, cornerRadius: 0))

    private func fitted(background: BackgroundStyle) throws -> CGImage {
        try Composer.composeFitted(screenshot: solid(80, 180, alpha: false), bezel: bezel,
                                   bezelImage: solid(100, 200, alpha: true),
                                   settings: ComposeSettings(background: background), canvas: (1000, 1000))
    }

    @Test func outputHasExactCanvasSizeAndNoAlpha() throws {
        let image = try fitted(background: .transparent)
        #expect(image.width == 1000 && image.height == 1000)
        let info = image.alphaInfo
        #expect(info == .noneSkipFirst || info == .noneSkipLast || info == .none)

        // PNG に書き出して読み戻しても、アルファチャンネルが無い
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageFile.writePNG(image, to: url)
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        // PNG の IHDR（先頭 8 バイトのシグネチャ + チャンク長/種別 8 バイト + 幅高さ 8 バイト + 深度 1 バイトの次）が色タイプ。2 = RGB、6 = RGBA
        let bytes = try Data(contentsOf: url)
        #expect(bytes[25] == 2)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1000)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 1000)
    }

    @Test func scalesUpAndCentersWithBackgroundMargins() throws {
        // 100x200 のベゼルを 1000x1000 へ: 倍率 5 → 500x1000、左右 250px ずつ余白
        let image = try fitted(background: .solid(RGBAColor(r: 0, g: 0, b: 1)))
        let data = try #require(image.dataProvider?.data as Data?)
        let bytesPerRow = image.bytesPerRow
        func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            let o = y * bytesPerRow + x * 4 // noneSkipFirst + little endian: B G R X
            return (data[o + 2], data[o + 1], data[o])
        }
        let margin = pixel(100, 500)
        #expect(margin.b == 255 && margin.r == 0) // 余白は背景の青
        let device = pixel(500, 500)
        #expect(device.r == 255 && device.b == 0) // 中央はベゼル/スクショ（赤）
    }

    @Test func sizesMatchOfficialRequiredOnes() {
        #expect(AppStoreSize.all.contains { $0.width == 1179 && $0.height == 2556 && $0.isRequired })
        #expect(AppStoreSize.all.contains { $0.width == 2064 && $0.height == 2752 && $0.isRequired })
        let phone = AppStoreSize.all.first { $0.width == 1320 }!
        #expect(phone.canvas(for: .portrait) == (1320, 2868))
        #expect(phone.canvas(for: .landscape) == (2868, 1320))
        let pad = AppStoreSize.all.first { $0.width == 2064 }!
        #expect(pad.canvas(for: .portrait) == (2064, 2752))
        #expect(pad.canvas(for: .landscape) == (2752, 2064))
        let mac = AppStoreSize.all.first { $0.family == .mac }!.canvas(for: .landscape)
        #expect(mac.width == 1280 && mac.height == 800) // Mac は向きで入れ替えない
    }
}
