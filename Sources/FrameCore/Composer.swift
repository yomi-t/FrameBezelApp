import Foundation
import CoreGraphics

public struct RGBAColor: Codable, Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

public enum BackgroundStyle: Codable, Equatable, Sendable {
    case solid(RGBAColor)
    /// angleDegrees: 0 = 左→右、90 = 上→下
    case gradient(start: RGBAColor, end: RGBAColor, angleDegrees: Double)
    case transparent
}

public enum FitMode: String, Codable, CaseIterable, Sendable {
    /// アスペクト比維持で画面領域に収める（余りは黒）
    case fit
    /// アスペクト比維持で画面領域を埋める（はみ出しは切り落とし）
    case fill
}

public struct ComposeSettings: Codable, Equatable, Sendable {
    public var background: BackgroundStyle
    public var fit: FitMode

    public init(background: BackgroundStyle, fit: FitMode = .fit) {
        self.background = background
        self.fit = fit
    }
}

/// フィル時の切り抜き位置・拡大率。画面領域に対する正規化値なので、プレビューと書き出しで同じ結果になる。
public struct ScreenCrop: Equatable, Sendable {
    public static let maxZoom = 4.0
    public static let identity = ScreenCrop()

    /// 1 = ちょうど画面領域を埋める大きさ。1〜maxZoom。
    public var zoom: Double
    /// 画像中心の移動量。画面領域の幅 / 高さを 1 とする。+x は右、+y は下。
    public var offsetX: Double
    public var offsetY: Double

    public init(zoom: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    /// zoom を範囲内に収め、画像が画面領域から外れて下地が見えないよう移動量を制限する。
    public func clamped(screenshotWidth sw: Double, screenshotHeight sh: Double,
                        screenWidth aw: Double, screenHeight ah: Double) -> ScreenCrop {
        let z = min(max(zoom, 1), Self.maxZoom)
        guard sw > 0, sh > 0, aw > 0, ah > 0 else { return ScreenCrop(zoom: z) }
        let ratio = max(aw / sw, ah / sh) * z
        let limitX = max(0, (sw * ratio - aw) / 2) / aw
        let limitY = max(0, (sh * ratio - ah) / 2) / ah
        return ScreenCrop(zoom: z, offsetX: min(max(offsetX, -limitX), limitX),
                          offsetY: min(max(offsetY, -limitY), limitY))
    }
}

public enum ComposeError: Error, LocalizedError {
    case contextCreationFailed
    case imageCreationFailed

    public var errorDescription: String? { "合成用のグラフィックスコンテキストを作れませんでした" }
}

/// 合成の中核。UI・ファイルに依存しない純粋な関数。
public enum Composer {
    /// 出力キャンバスはベゼル画像のサイズそのもの（外側に余白は付けない）。
    public static func outputSize(bezel: Bezel, scale: Double = 1) -> (width: Int, height: Int) {
        let s = max(0.01, scale)
        return (max(1, Int((Double(bezel.imageWidth) * s).rounded())),
                max(1, Int((Double(bezel.imageHeight) * s).rounded())))
    }

    /// 背景 → スクショ（画面領域に角丸クリップ）→ ベゼル の順に重ねる。
    /// scale = 1 でベゼル PNG 等倍（書き出し用）、< 1 でプレビュー用の縮小出力。
    public static func compose(
        screenshot: CGImage,
        bezel: Bezel,
        bezelImage: CGImage,
        settings: ComposeSettings,
        crop: ScreenCrop = .identity,
        scale: Double = 1
    ) throws -> CGImage {
        let size = outputSize(bezel: bezel, scale: scale)
        let logicalW = Double(bezel.imageWidth)
        let logicalH = Double(bezel.imageHeight)

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { throw ComposeError.contextCreationFailed }

        // 以降は「ベゼル等倍ピクセル」の論理座標で描く（丸め誤差を出力サイズ側に吸収）
        ctx.scaleBy(x: Double(size.width) / logicalW, y: Double(size.height) / logicalH)
        ctx.interpolationQuality = .high

        // 1. 背景
        let canvas = CGRect(x: 0, y: 0, width: logicalW, height: logicalH)
        switch settings.background {
        case .transparent:
            break
        case .solid(let color):
            ctx.setFillColor(color.cgColor)
            ctx.fill(canvas)
        case .gradient(let start, let end, let angle):
            if let gradient = CGGradient(colorsSpace: space, colors: [start.cgColor, end.cgColor] as CFArray, locations: [0, 1]) {
                let rad = angle * .pi / 180
                // CG は y 上向きなので、画面上の「下向き」角度の y 成分を反転する
                let dx = cos(rad)
                let dy = -sin(rad)
                let half = (abs(cos(rad)) * logicalW + abs(sin(rad)) * logicalH) / 2
                let c = CGPoint(x: logicalW / 2, y: logicalH / 2)
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: c.x - dx * half, y: c.y - dy * half),
                    end: CGPoint(x: c.x + dx * half, y: c.y + dy * half),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        }

        // 2. スクショ。aperture は左上原点なので CG（左下原点）に変換する
        let a = bezel.aperture
        let screen = CGRect(x: a.x, y: Double(bezel.imageHeight) - a.y - a.height,
                            width: a.width, height: a.height)
        let radius = max(0, min(a.cornerRadius, min(screen.width, screen.height) / 2))
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        // アスペクト比が合わないときの余白が背景透け（透明背景なら抜け）にならないよう、画面は黒で下地を敷く
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(screen)
        let sw = Double(screenshot.width)
        let sh = Double(screenshot.height)
        var drawW: Double
        var drawH: Double
        var center = CGPoint(x: screen.midX, y: screen.midY)
        if settings.fit == .fit {
            let ratio = min(screen.width / sw, screen.height / sh)
            drawW = sw * ratio
            drawH = sh * ratio
        } else {
            // フィル：切り抜きの拡大率・位置を反映（CG は y 上向きなので y は反転）
            let c = crop.clamped(screenshotWidth: sw, screenshotHeight: sh,
                                 screenWidth: screen.width, screenHeight: screen.height)
            let ratio = max(screen.width / sw, screen.height / sh) * c.zoom
            drawW = sw * ratio
            drawH = sh * ratio
            center.x += c.offsetX * screen.width
            center.y -= c.offsetY * screen.height
        }
        ctx.draw(screenshot, in: CGRect(x: center.x - drawW / 2, y: center.y - drawH / 2,
                                        width: drawW, height: drawH))
        ctx.restoreGState()

        // 3. ベゼル
        ctx.draw(bezelImage, in: CGRect(x: 0, y: 0, width: Double(bezel.imageWidth), height: Double(bezel.imageHeight)))

        guard let result = ctx.makeImage() else { throw ComposeError.imageCreationFailed }
        return result
    }
}
