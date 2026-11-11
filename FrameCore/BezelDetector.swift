import Foundation
import CoreGraphics

public enum BezelDetectorError: Error, LocalizedError {
    case cannotReadPixels
    case noScreenRegion

    public var errorDescription: String? {
        switch self {
        case .cannotReadPixels: return "ベゼル画像のピクセルを読み取れませんでした"
        case .noScreenRegion: return "画面領域（枠で囲まれた透明部分）が見つかりませんでした"
        }
    }
}

/// ベゼル PNG のアルファ走査で画面領域を検出する。
public enum BezelDetector {
    /// これ未満のアルファを「透明」とみなす。縁のアンチエイリアスを画面側に含めないため半値にする。
    static let transparentThreshold: UInt8 = 128

    public static func detect(image: CGImage) throws -> Aperture {
        let w = image.width
        let h = image.height
        guard w > 2, h > 2 else { throw BezelDetectorError.cannotReadPixels }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { throw BezelDetectorError.cannotReadPixels }
        // 以降 memory の 1 行目 = 画像の上端（左上原点）として扱える。

        let threshold = transparentThreshold
        func transparent(_ x: Int, _ y: Int) -> Bool { pixels[(y * w + x) * 4 + 3] < threshold }

        // 透明部分は「画面」と「ベゼル外側（角の外・余白）」の2種類ある。
        // 外側は画像の縁から連結しているので、縁から塗りつぶして除外する。
        var outside = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        func seed(_ x: Int, _ y: Int) {
            let i = y * w + x
            if !outside[i] && transparent(x, y) {
                outside[i] = true
                stack.append(i)
            }
        }
        for x in 0..<w { seed(x, 0); seed(x, h - 1) }
        for y in 0..<h { seed(0, y); seed(w - 1, y) }
        while let i = stack.popLast() {
            let x = i % w
            let y = i / w
            if x > 0 { seed(x - 1, y) }
            if x < w - 1 { seed(x + 1, y) }
            if y > 0 { seed(x, y - 1) }
            if y < h - 1 { seed(x, y + 1) }
        }

        func isScreen(_ x: Int, _ y: Int) -> Bool { !outside[y * w + x] && transparent(x, y) }

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where isScreen(x, y) {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { throw BezelDetectorError.noScreenRegion }

        let bw = maxX - minX + 1
        let bh = maxY - minY + 1

        // 角丸推定: 各角から対角線方向に進み、最初に画面ピクセルに当たるまでの距離 k を測る。
        // 半径 r の円弧は角から対角線上で r(1 - 1/√2) の位置を通るので r = k / (1 - 1/√2)。
        let corners: [(x: Int, y: Int, dx: Int, dy: Int)] = [
            (minX, minY, 1, 1), (maxX, minY, -1, 1), (minX, maxY, 1, -1), (maxX, maxY, -1, -1)
        ]
        var radii: [Double] = []
        for c in corners {
            for k in 0..<(min(bw, bh) / 2) where isScreen(c.x + c.dx * k, c.y + c.dy * k) {
                radii.append(Double(k) / (1 - 1 / 2.0.squareRoot()))
                break
            }
        }
        let maxRadius = Double(min(bw, bh)) / 2
        let radius = radii.isEmpty ? 0 : min(radii.reduce(0, +) / Double(radii.count), maxRadius)

        return Aperture(x: Double(minX), y: Double(minY), width: Double(bw), height: Double(bh),
                        cornerRadius: radius.rounded())
    }
}
