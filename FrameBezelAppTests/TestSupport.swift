import Foundation
import CoreGraphics
import ImageIO
@testable import FrameBezelApp

/// テスト用の画像・ベゼル・一時フォルダの共通ヘルパー。
enum TestSupport {
    struct RGBA: Equatable {
        var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// 使い終わったら `remove` で消す一時フォルダ。本物の Application Support には触れない。
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FrameBezelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    /// 専用の UserDefaults（テストごとに空）。
    static func makeDefaults() -> (defaults: UserDefaults, cleanup: () -> Void) {
        let name = "FrameBezelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    // MARK: 画像

    /// 単色の不透明画像（アルファ無し）。
    static func solid(_ w: Int, _ h: Int, r: Double = 1, g: Double = 0, b: Double = 0) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// 左半分が赤・右半分が青など、向きの確認に使う 4 象限画像（左上=赤、右上=緑、左下=青、右下=黄）。
    static func quadrants(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        func fill(_ r: Double, _ g: Double, _ b: Double, _ rect: CGRect) {
            ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
            ctx.fill(rect)
        }
        let hw = CGFloat(w) / 2, hh = CGFloat(h) / 2
        // CG は y 上向きなので、画像の上側は y が大きい側
        fill(1, 0, 0, CGRect(x: 0, y: hh, width: hw, height: hh))
        fill(0, 1, 0, CGRect(x: hw, y: hh, width: hw, height: hh))
        fill(0, 0, 1, CGRect(x: 0, y: 0, width: hw, height: hh))
        fill(1, 1, 0, CGRect(x: hw, y: 0, width: hw, height: hh))
        return ctx.makeImage()!
    }

    /// 擬似ベゼル: 不透明な黒の枠に、`screen`（左上原点）の透明な窓を開けた画像。
    /// `outerCornerClear` を true にすると、画像の四隅（枠の外側）も透明にする。
    static func bezelImage(width w: Int, height h: Int, screen: CGRect, outerCornerClear: Bool = false) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if outerCornerClear {
            ctx.clear(CGRect(x: 0, y: h - 2, width: 2, height: 2))
            ctx.clear(CGRect(x: w - 2, y: h - 2, width: 2, height: 2))
            ctx.clear(CGRect(x: 0, y: 0, width: 2, height: 2))
            ctx.clear(CGRect(x: w - 2, y: 0, width: 2, height: 2))
        }
        ctx.clear(CGRect(x: screen.minX, y: CGFloat(h) - screen.maxY, width: screen.width, height: screen.height))
        return ctx.makeImage()!
    }

    /// 窓の角を丸くした擬似ベゼル（半径 `radius`）。
    static func roundedBezelImage(width w: Int, height h: Int, screen: CGRect, radius: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let rect = CGRect(x: screen.minX, y: CGFloat(h) - screen.maxY, width: screen.width, height: screen.height)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.clear(rect)
        ctx.restoreGState()
        return ctx.makeImage()!
    }

    /// 窓の四隅の角丸が角ごとに違う擬似ベゼル（`radii` は画像を見たままの左上・右上・右下・左下）。
    static func bezelImage(width w: Int, height h: Int, screen: CGRect, radii: CornerRadii) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let rect = CGRect(x: screen.minX, y: CGFloat(h) - screen.maxY, width: screen.width, height: screen.height)
        let a = Aperture(x: 0, y: 0, width: screen.width, height: screen.height, cornerRadius: 0, cornerRadii: radii)
        ctx.saveGState()
        ctx.addPath(a.clipPath(in: rect))
        ctx.clip()
        ctx.clear(rect)
        ctx.restoreGState()
        return ctx.makeImage()!
    }

    static func writeBezelPNG(to url: URL, width: Int = 100, height: Int = 200,
                              screen: CGRect = CGRect(x: 20, y: 20, width: 60, height: 160)) throws {
        try ImageFile.writePNG(bezelImage(width: width, height: height, screen: screen), to: url)
    }

    /// 画像の (x, y)（左上原点）のピクセルを RGBA（非乗算）で読む。
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> RGBA {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let o = (y * w + x) * 4
        let a = buf[o + 3]
        guard a > 0, a < 255 else { return RGBA(r: buf[o], g: buf[o + 1], b: buf[o + 2], a: a) }
        func un(_ v: UInt8) -> UInt8 { UInt8(min(255, (Int(v) * 255 + Int(a) / 2) / Int(a))) }
        return RGBA(r: un(buf[o]), g: un(buf[o + 1]), b: un(buf[o + 2]), a: a)
    }

    // MARK: ベゼル定義

    static func bezel(
        name: String = "T", file: String = "t.png", width: Int = 100, height: Int = 200,
        aperture: Aperture = Aperture(x: 10, y: 10, width: 80, height: 180, cornerRadius: 0),
        model: String? = nil, orientation: BezelOrientation? = nil, color: String? = nil, variant: String? = nil
    ) -> Bezel {
        Bezel(name: name, bezelFile: file, imageWidth: width, imageHeight: height, aperture: aperture,
              model: model, orientation: orientation, color: color, variant: variant)
    }

    static func aperture(_ w: Double, _ h: Double) -> Aperture {
        Aperture(x: 0, y: 0, width: w, height: h, cornerRadius: 0)
    }

    static func aperture(_ x: Double, _ y: Double, _ w: Double, _ h: Double, r: Double = 0) -> Aperture {
        Aperture(x: x, y: y, width: w, height: h, cornerRadius: r)
    }
}
