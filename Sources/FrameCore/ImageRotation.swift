import Foundation
import CoreGraphics

/// スクショの向き。時計回りの 90° 単位。
public struct Rotation: Equatable, Sendable {
    /// 時計回りの 90° 回転数（0〜3）
    public private(set) var quarterTurns: Int

    public static let none = Rotation(quarterTurns: 0)

    public init(quarterTurns: Int) {
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
    }

    public var isIdentity: Bool { quarterTurns == 0 }
    /// 90° / 270° のとき幅と高さが入れ替わる
    public var swapsAxes: Bool { quarterTurns % 2 == 1 }

    public func rotatedClockwise() -> Rotation { Rotation(quarterTurns: quarterTurns + 1) }
    public func rotatedCounterClockwise() -> Rotation { Rotation(quarterTurns: quarterTurns - 1) }
}

public enum ImageRotation {
    /// 画像を時計回りに回転した新しい CGImage を返す。回転なしなら元画像をそのまま返す。
    public static func rotate(_ image: CGImage, _ rotation: Rotation) -> CGImage? {
        if rotation.isIdentity { return image }
        let w = Double(image.width)
        let h = Double(image.height)
        let outW = rotation.swapsAxes ? image.height : image.width
        let outH = rotation.swapsAxes ? image.width : image.height

        guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        ctx.interpolationQuality = .high

        // CG は y 上向き。ソース点 (x, y) の写り先：
        // 時計回り90°: (y, w − x) / 180°: (w − x, h − y) / 反時計回り90°: (h − y, x)
        switch rotation.quarterTurns {
        case 1: ctx.concatenate(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w))
        case 2: ctx.concatenate(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h))
        default: ctx.concatenate(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0))
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
