// アイコン案の生成スクリプト（アプリアイコン 1024x1024、全面塗り・角丸なし）。
// 実行: swift AppIconDraft/make_icon.swift  → AppIconDraft/icon_1024.png
import CoreGraphics
import ImageIO
import Foundation

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { color($0.0) } as CFArray, locations: stops.map { $0.1 })!
}
func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 角丸にせず、1024x1024 全面を塗りつぶす（形のマスクは OS 側に任せる）
let body = CGRect(x: 0, y: 0, width: 1024, height: 1024)
let bodyPath = CGPath(rect: body, transform: nil)

// 背景グラデーション
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
ctx.drawLinearGradient(gradient([(0x4F7CFF, 0), (0x6A4DF0, 0.55), (0x9B3FE0, 1)]),
                       start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
// 上部のやわらかい光
ctx.drawRadialGradient(CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!,
                       startCenter: CGPoint(x: 400, y: 900), startRadius: 0, endCenter: CGPoint(x: 400, y: 900), endRadius: 520, options: [])

// スマホ本体（ベゼル）
let phone = CGRect(x: 512 - 175, y: 512 - 325, width: 350, height: 650)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0x10104A, 0.55))
ctx.addPath(roundedPath(phone, 78)); ctx.setFillColor(color(0x15151A)); ctx.fillPath()
ctx.restoreGState()
// フレームの縁（金属の細いハイライト）
ctx.addPath(roundedPath(phone, 78)); ctx.setStrokeColor(color(0xD9DCE8)); ctx.setLineWidth(7); ctx.strokePath()
ctx.addPath(roundedPath(phone.insetBy(dx: 7, dy: 7), 71)); ctx.setStrokeColor(color(0x000000, 0.9)); ctx.setLineWidth(6); ctx.strokePath()

// 画面（スクショの壁紙風）
let screen = phone.insetBy(dx: 20, dy: 20)
ctx.saveGState()
ctx.addPath(roundedPath(screen, 60)); ctx.clip()
ctx.drawLinearGradient(gradient([(0xFFB36B, 0), (0xFF5F8D, 0.5), (0x6A5BFF, 1)]),
                       start: CGPoint(x: screen.minX, y: screen.maxY), end: CGPoint(x: screen.maxX, y: screen.minY), options: [])
// 壁紙の丸いアクセント
ctx.setFillColor(color(0xFFFFFF, 0.22))
ctx.fillEllipse(in: CGRect(x: screen.midX - 20, y: screen.minY + 70, width: 170, height: 170))
ctx.setFillColor(color(0xFFFFFF, 0.14))
ctx.fillEllipse(in: CGRect(x: screen.minX - 40, y: screen.midY - 30, width: 190, height: 190))
ctx.restoreGState()

// ダイナミックアイランド
let island = CGRect(x: phone.midX - 52, y: phone.maxY - 20 - 20 - 38, width: 104, height: 34)
ctx.addPath(roundedPath(island, 17)); ctx.setFillColor(color(0x000000)); ctx.fillPath()

// 画面のガラス反射
ctx.saveGState()
ctx.addPath(roundedPath(screen, 60)); ctx.clip()
ctx.move(to: CGPoint(x: screen.minX, y: screen.maxY))
ctx.addLine(to: CGPoint(x: screen.minX + 190, y: screen.maxY))
ctx.addLine(to: CGPoint(x: screen.minX, y: screen.maxY - 330))
ctx.closePath()
ctx.setFillColor(color(0xFFFFFF, 0.14)); ctx.fillPath()
ctx.restoreGState()

ctx.restoreGState() // 本体クリップ解除

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIconDraft/icon_1024.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
print(out.path)
