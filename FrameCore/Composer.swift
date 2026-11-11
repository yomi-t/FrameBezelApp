import Foundation
import CoreGraphics

nonisolated public struct RGBAColor: Codable, Equatable, Sendable {
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

nonisolated public enum BackgroundStyle: Codable, Equatable, Sendable {
    case solid(RGBAColor)
    /// angleDegrees: 0 = 左→右、90 = 上→下
    case gradient(start: RGBAColor, end: RGBAColor, angleDegrees: Double)
    case transparent
}

nonisolated public struct ComposeSettings: Codable, Equatable, Sendable {
    public var background: BackgroundStyle

    public init(background: BackgroundStyle) {
        self.background = background
    }
}

/// スクショの拡大率と位置。画面領域に対する正規化値なので、プレビューと書き出しで同じ結果になる。
/// 「収める / 埋める」は状態ではなく、この値の初期化操作（`.fit` / `.fill`）として扱う。
nonisolated public struct ScreenCrop: Equatable, Sendable {
    public static let maxZoom = 4.0
    /// 縮小の下限。「全体が収まる大きさ」のこの割合まで小さくできる（画面領域より小さく置ける）。
    public static let minScaleOfFit = 0.1
    /// 全体が画面領域に収まる大きさ。zoom が 0 以下の値は `clamped` で「収まる大きさ」に解決される。
    public static let fit = ScreenCrop(zoom: 0)
    /// ちょうど画面領域を埋める大きさ。
    public static let fill = ScreenCrop(zoom: 1)

    /// 1 = 画面領域を埋める大きさ。1 未満で縮み、全体が収まる大きさより小さくもできる。
    public var zoom: Double
    /// 画像中心の移動量。画面領域の幅 / 高さを 1 とする。+x は右、+y は下。
    public var offsetX: Double
    public var offsetY: Double

    public init(zoom: Double = 1, offsetX: Double = 0, offsetY: Double = 0) {
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    /// 全体が画面領域に収まる zoom（縦横比が合っていれば 1）。
    private static func fitZoom(sw: Double, sh: Double, aw: Double, ah: Double) -> Double {
        min(aw / sw, ah / sh) / max(aw / sw, ah / sh)
    }

    /// zoom の有効範囲に丸める。0 以下は「収まる大きさ」の意味。
    private static func clampZoom(_ zoom: Double, sw: Double, sh: Double, aw: Double, ah: Double) -> Double {
        let fit = fitZoom(sw: sw, sh: sh, aw: aw, ah: ah)
        return zoom <= 0 ? fit : min(max(zoom, fit * minScaleOfFit), maxZoom)
    }

    /// zoom を有効範囲に収め、画像を画面領域の外へ出しすぎないよう移動量を制限する。
    /// 画像が画面領域より大きい軸は下地（黒）が見えない範囲、小さい軸は画面領域からはみ出さない範囲で動かせる。
    public func clamped(screenshotWidth sw: Double, screenshotHeight sh: Double,
                        screenWidth aw: Double, screenHeight ah: Double) -> ScreenCrop {
        guard sw > 0, sh > 0, aw > 0, ah > 0 else { return ScreenCrop(zoom: min(max(zoom, 1), Self.maxZoom)) }
        let z = Self.clampZoom(zoom, sw: sw, sh: sh, aw: aw, ah: ah)
        let ratio = max(aw / sw, ah / sh) * z
        let limitX = abs(sw * ratio - aw) / 2 / aw
        let limitY = abs(sh * ratio - ah) / 2 / ah
        return ScreenCrop(zoom: z, offsetX: min(max(offsetX, -limitX), limitX),
                          offsetY: min(max(offsetY, -limitY), limitY))
    }

    /// 画像が描かれる矩形。ベゼル PNG の座標系（左上原点、ピクセル単位）。選択枠の表示に使う。
    public func imageRect(screenshotWidth sw: Double, screenshotHeight sh: Double, aperture a: Aperture) -> CGRect {
        let ratio = max(a.width / sw, a.height / sh) * zoom
        let w = sw * ratio
        let h = sh * ratio
        let cx = a.x + a.width / 2 + offsetX * a.width
        let cy = a.y + a.height / 2 + offsetY * a.height
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// 画像の幅を指定の px にする（中心を保つ。縦横比は固定）。数値入力用。
    public func withImageWidth(_ width: Double, screenshotWidth sw: Double, screenshotHeight sh: Double,
                               aperture a: Aperture) -> ScreenCrop {
        let rect = imageRect(screenshotWidth: sw, screenshotHeight: sh, aperture: a)
        guard width > 0, rect.width > 0 else { return self }
        return resized(by: width / rect.width, anchor: CGPoint(x: rect.midX, y: rect.midY),
                       screenshotWidth: sw, screenshotHeight: sh, aperture: a)
    }

    public func withImageHeight(_ height: Double, screenshotWidth sw: Double, screenshotHeight sh: Double,
                                aperture a: Aperture) -> ScreenCrop {
        let rect = imageRect(screenshotWidth: sw, screenshotHeight: sh, aperture: a)
        guard height > 0, rect.height > 0 else { return self }
        return resized(by: height / rect.height, anchor: CGPoint(x: rect.midX, y: rect.midY),
                       screenshotWidth: sw, screenshotHeight: sh, aperture: a)
    }

    /// 画像の左上を、画面領域の左上を原点とした (x, y) px に置く。数値入力用。
    public func withImageOrigin(x: Double, y: Double, screenshotWidth sw: Double, screenshotHeight sh: Double,
                                aperture a: Aperture) -> ScreenCrop {
        let rect = imageRect(screenshotWidth: sw, screenshotHeight: sh, aperture: a)
        let cx = a.x + x + rect.width / 2
        let cy = a.y + y + rect.height / 2
        return ScreenCrop(zoom: zoom, offsetX: (cx - (a.x + a.width / 2)) / a.width,
                          offsetY: (cy - (a.y + a.height / 2)) / a.height)
    }

    /// 画像の辺が画面領域の辺（上下左右）に `threshold`（ベゼル px）以内まで近づいたら、ぴったり重なる位置へ吸着させる。
    /// 移動ドラッグ用。縦横それぞれ独立に判定し、吸着したかも返す。
    public func snappedPosition(screenshotWidth sw: Double, screenshotHeight sh: Double,
                                aperture a: Aperture, threshold: Double) -> (crop: ScreenCrop, snapped: Bool) {
        let r = imageRect(screenshotWidth: sw, screenshotHeight: sh, aperture: a)
        let dx = Self.nearest([a.x - r.minX, a.x + a.width - r.maxX], within: threshold)
        let dy = Self.nearest([a.y - r.minY, a.y + a.height - r.maxY], within: threshold)
        var c = self
        if let dx { c.offsetX += dx / a.width }
        if let dy { c.offsetY += dy / a.height }
        return (c, dx != nil || dy != nil)
    }

    /// 角ハンドルの拡大・縮小用。倍率を、次のどれかが成り立つ値へ吸着させる。
    /// ・画像の幅（高さ）が画面領域の幅（高さ）と一致 ・動かしている角の辺が画面領域の辺と重なる
    /// `moved` は動かしている角、`anchor` は固定している対角（どちらもドラッグ開始時のベゼル座標）。
    public static func snapFactor(_ factor: Double, moved: CGPoint, anchor: CGPoint, aperture a: Aperture,
                                  threshold: Double) -> (factor: Double, snapped: Bool) {
        let w0 = abs(moved.x - anchor.x), h0 = abs(moved.y - anchor.y)
        var candidates: [(factor: Double, distance: Double)] = []
        if w0 > 0 {
            candidates.append((a.width / w0, abs(w0 * factor - a.width)))
            for t in [a.x, a.x + a.width] {
                let f = (t - anchor.x) / (moved.x - anchor.x)
                candidates.append((f, abs(anchor.x + (moved.x - anchor.x) * factor - t)))
            }
        }
        if h0 > 0 {
            candidates.append((a.height / h0, abs(h0 * factor - a.height)))
            for t in [a.y, a.y + a.height] {
                let f = (t - anchor.y) / (moved.y - anchor.y)
                candidates.append((f, abs(anchor.y + (moved.y - anchor.y) * factor - t)))
            }
        }
        let hit = candidates.filter { $0.factor > 0 && $0.distance <= threshold }.min { $0.distance < $1.distance }
        return hit.map { ($0.factor, true) } ?? (factor, false)
    }

    private static func nearest(_ deltas: [Double], within threshold: Double) -> Double? {
        deltas.filter { abs($0) <= threshold }.min { abs($0) < abs($1) }
    }

    /// `anchor`（ベゼル座標）を固定したまま `factor` 倍に拡大・縮小する。角ハンドルのドラッグ用。
    /// 倍率は zoom の有効範囲に丸める。移動量の丸めは呼び出し側（`clamped`）に任せる。
    public func resized(by factor: Double, anchor: CGPoint, screenshotWidth sw: Double, screenshotHeight sh: Double,
                        aperture a: Aperture) -> ScreenCrop {
        guard sw > 0, sh > 0, a.width > 0, a.height > 0, zoom > 0 else { return self }
        let newZoom = Self.clampZoom(zoom * factor, sw: sw, sh: sh, aw: a.width, ah: a.height)
        let actual = newZoom / zoom
        let rect = imageRect(screenshotWidth: sw, screenshotHeight: sh, aperture: a)
        let cx = anchor.x + (rect.midX - anchor.x) * actual
        let cy = anchor.y + (rect.midY - anchor.y) * actual
        return ScreenCrop(zoom: newZoom, offsetX: (cx - (a.x + a.width / 2)) / a.width,
                          offsetY: (cy - (a.y + a.height / 2)) / a.height)
    }
}

nonisolated public enum ComposeError: Error, LocalizedError {
    case contextCreationFailed
    case imageCreationFailed

    public var errorDescription: String? { "合成用のグラフィックスコンテキストを作れませんでした" }
}

/// 合成の中核。UI・ファイルに依存しない純粋な関数。
nonisolated public enum Composer {
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
        crop: ScreenCrop = .fit,
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

        drawBackground(settings.background, in: ctx, rect: CGRect(x: 0, y: 0, width: logicalW, height: logicalH), space: space)
        drawDevice(screenshot: screenshot, bezel: bezel, bezelImage: bezelImage, crop: crop, in: ctx)

        guard let result = ctx.makeImage() else { throw ComposeError.imageCreationFailed }
        return result
    }

    /// 指定キャンバス（App Store Connect の提出サイズなど）いっぱいに、ベゼルを縦横比を保ったまま最大に拡大して中央へ置く。
    /// 余白と透明部分は背景で埋める。App Store Connect はアルファチャンネルを受け付けないため、
    /// 結果は常に不透明（アルファ無し）で、背景が透明のときは白で埋める。
    public static func composeFitted(
        screenshot: CGImage,
        bezel: Bezel,
        bezelImage: CGImage,
        settings: ComposeSettings,
        crop: ScreenCrop = .fit,
        canvas: (width: Int, height: Int)
    ) throws -> CGImage {
        guard canvas.width > 0, canvas.height > 0 else { throw ComposeError.contextCreationFailed }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { throw ComposeError.contextCreationFailed }
        ctx.interpolationQuality = .high

        let canvasW = Double(canvas.width), canvasH = Double(canvas.height)
        // 半透明の背景色でもアルファが残らないよう、まず白で下地を敷く
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
        drawBackground(settings.background, in: ctx, rect: CGRect(x: 0, y: 0, width: canvasW, height: canvasH), space: space)

        let scale = min(canvasW / Double(bezel.imageWidth), canvasH / Double(bezel.imageHeight))
        ctx.translateBy(x: (canvasW - Double(bezel.imageWidth) * scale) / 2,
                        y: (canvasH - Double(bezel.imageHeight) * scale) / 2)
        ctx.scaleBy(x: scale, y: scale)
        drawDevice(screenshot: screenshot, bezel: bezel, bezelImage: bezelImage, crop: crop, in: ctx)

        guard let result = ctx.makeImage() else { throw ComposeError.imageCreationFailed }
        return result
    }

    private static func drawBackground(_ style: BackgroundStyle, in ctx: CGContext, rect: CGRect, space: CGColorSpace) {
        switch style {
        case .transparent:
            break
        case .solid(let color):
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        case .gradient(let start, let end, let angle):
            if let gradient = CGGradient(colorsSpace: space, colors: [start.cgColor, end.cgColor] as CFArray, locations: [0, 1]) {
                let rad = angle * .pi / 180
                // CG は y 上向きなので、画面上の「下向き」角度の y 成分を反転する
                let dx = cos(rad)
                let dy = -sin(rad)
                let half = (abs(cos(rad)) * rect.width + abs(sin(rad)) * rect.height) / 2
                let c = CGPoint(x: rect.midX, y: rect.midY)
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: c.x - dx * half, y: c.y - dy * half),
                    end: CGPoint(x: c.x + dx * half, y: c.y + dy * half),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        }
    }

    /// スクショ（画面領域に角丸クリップ）→ ベゼルの順に重ねる。座標はベゼル等倍の論理座標（左下原点の CG 座標系）。
    private static func drawDevice(screenshot: CGImage, bezel: Bezel, bezelImage: CGImage, crop: ScreenCrop, in ctx: CGContext) {
        // aperture は左上原点なので CG（左下原点）に変換する
        let a = bezel.aperture
        let screen = CGRect(x: a.x, y: Double(bezel.imageHeight) - a.y - a.height,
                            width: a.width, height: a.height)
        ctx.saveGState()
        ctx.addPath(a.clipPath(in: screen)) // 角ごとに半径が違う画面（Duo の外側など）にも合わせる
        ctx.clip()
        // アスペクト比が合わないときの余白が背景透け（透明背景なら抜け）にならないよう、画面は黒で下地を敷く
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(screen)
        let sw = Double(screenshot.width)
        let sh = Double(screenshot.height)
        // CG は y 上向きなので y は反転
        let c = crop.clamped(screenshotWidth: sw, screenshotHeight: sh,
                             screenWidth: screen.width, screenHeight: screen.height)
        let ratio = max(screen.width / sw, screen.height / sh) * c.zoom
        let drawW = sw * ratio
        let drawH = sh * ratio
        var center = CGPoint(x: screen.midX, y: screen.midY)
        center.x += c.offsetX * screen.width
        center.y -= c.offsetY * screen.height
        ctx.draw(screenshot, in: CGRect(x: center.x - drawW / 2, y: center.y - drawH / 2,
                                        width: drawW, height: drawH))
        ctx.restoreGState()

        ctx.draw(bezelImage, in: CGRect(x: 0, y: 0, width: Double(bezel.imageWidth), height: Double(bezel.imageHeight)))
    }
}
