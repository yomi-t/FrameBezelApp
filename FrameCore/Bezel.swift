import Foundation
import CoreGraphics

/// 四隅それぞれの角丸の半径（ベゼル PNG のピクセル単位）。左上・右上・右下・左下は、画像を見たままの位置。
nonisolated public struct CornerRadii: Codable, Equatable, Sendable {
    public var topLeft: Double
    public var topRight: Double
    public var bottomRight: Double
    public var bottomLeft: Double

    public init(topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public init(uniform r: Double) { self.init(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }

    public var average: Double { (topLeft + topRight + bottomRight + bottomLeft) / 4 }
    public var isUniform: Bool { topLeft == topRight && topRight == bottomRight && bottomRight == bottomLeft }

    /// 画像を時計回りに 90° 回したときの四隅（左上だった角が右上へ移る）
    public func rotatedClockwise() -> CornerRadii {
        CornerRadii(topLeft: bottomLeft, topRight: topLeft, bottomRight: topRight, bottomLeft: bottomRight)
    }

    /// 反時計回りに 90° 回したとき（左上だった角が左下へ移る）
    public func rotatedCounterClockwise() -> CornerRadii {
        CornerRadii(topLeft: topRight, topRight: bottomRight, bottomRight: bottomLeft, bottomLeft: topLeft)
    }

    /// 辺の長さに収まるよう、隣り合う角の半径の合計が辺を超えるときは全体を縮める（CSS の border-radius と同じ扱い）。
    public func fitted(width: Double, height: Double) -> CornerRadii {
        var f = 1.0
        for (sum, side) in [(topLeft + topRight, width), (bottomLeft + bottomRight, width),
                            (topLeft + bottomLeft, height), (topRight + bottomRight, height)] where sum > side && sum > 0 {
            f = min(f, side / sum)
        }
        return CornerRadii(topLeft: max(0, topLeft * f), topRight: max(0, topRight * f),
                           bottomRight: max(0, bottomRight * f), bottomLeft: max(0, bottomLeft * f))
    }
}

/// 画面領域。座標はベゼル PNG のピクセル単位で、原点は画像の左上（y は下向き）。
/// 角丸は `cornerRadius`（四隅共通）が基本で、角ごとに違うデバイス（Duo の外側の画面など）は `cornerRadii` を持つ。
nonisolated public struct Aperture: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// 四隅共通の半径。`cornerRadii` があるときは、その平均（古いデータ・簡易表示用）
    public var cornerRadius: Double
    /// 角ごとに違うときだけ持つ。無ければ四隅とも `cornerRadius`
    public var cornerRadii: CornerRadii?

    public init(x: Double, y: Double, width: Double, height: Double, cornerRadius: Double, cornerRadii: CornerRadii? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.cornerRadii = cornerRadii
    }

    /// 実際に使う四隅の半径
    public var radii: CornerRadii { cornerRadii ?? CornerRadii(uniform: cornerRadius) }

    /// 画面領域の切り抜きの形。`rect` は描画先（CG 座標＝左下原点）の矩形。四隅の半径は辺に収まるよう縮める。
    public func clipPath(in rect: CGRect) -> CGPath {
        let r = radii.fitted(width: Double(rect.width), height: Double(rect.height))
        let path = CGMutablePath()
        let (minX, maxX, minY, maxY) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        path.move(to: CGPoint(x: minX + r.bottomLeft, y: minY))
        path.addLine(to: CGPoint(x: maxX - r.bottomRight, y: minY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + r.bottomRight), radius: r.bottomRight)
        path.addLine(to: CGPoint(x: maxX, y: maxY - r.topRight))
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - r.topRight, y: maxY), radius: r.topRight)
        path.addLine(to: CGPoint(x: minX + r.topLeft, y: maxY))
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - r.topLeft), radius: r.topLeft)
        path.addLine(to: CGPoint(x: minX, y: minY + r.bottomLeft))
        path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + r.bottomLeft, y: minY), radius: r.bottomLeft)
        path.closeSubpath()
        return path
    }
}

nonisolated public enum BezelOrientation: String, Codable, CaseIterable, Sendable {
    case portrait, landscape

    public var label: String { self == .portrait ? "縦" : "横" }
}

/// ベゼル定義（仕様 §7 の JSON 形式 + 機種/向き/色の任意フィールド）。
/// `model` / `orientation` / `color` は後から足した任意項目で、無い旧 JSON もそのまま読める。
nonisolated public struct Bezel: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var bezelFile: String
    public var imageWidth: Int
    public var imageHeight: Int
    public var aperture: Aperture
    /// 機種名（フォルダ名）。無ければ `name` で代用する。
    public var model: String?
    public var orientation: BezelOrientation?
    /// フレームの色。色違いが無い素材は nil。
    public var color: String?
    /// 同じ機種・向き・色でも画面の形態が違うもの（Duo の `Inner Open` / `Outer Closed` / `Outer Open` など）。無ければ nil。
    public var variant: String?

    public var id: String { bezelFile }

    public init(name: String, bezelFile: String, imageWidth: Int, imageHeight: Int, aperture: Aperture,
                model: String? = nil, orientation: BezelOrientation? = nil, color: String? = nil, variant: String? = nil) {
        self.name = name
        self.bezelFile = bezelFile
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.aperture = aperture
        self.model = model
        self.orientation = orientation
        self.color = color
        self.variant = variant
    }

    /// 画面や書き出しファイル名に使う、機種の正式名称（`Bezel` の接頭辞や色は付けない）。
    public var modelName: String { BezelNaming.officialName(model ?? name) }

    /// 向きが未設定の旧データは、画面領域の縦横から推定する。
    public var effectiveOrientation: BezelOrientation {
        orientation ?? (aperture.width > aperture.height ? .landscape : .portrait)
    }

    /// 登録されているベゼルを 90° 回した定義（画像サイズ・画面領域・向きを入れ替える。bezelFile など他の項目は同じ）。
    /// 画像側は `ImageRotation` で同じ向きに回す（`Bezel.quarterTurns(for:)`）。
    public func turned(to target: BezelOrientation) -> Bezel {
        guard effectiveOrientation != target else { return self }
        var b = self
        let w = Double(imageWidth), h = Double(imageHeight)
        let a = aperture
        b.imageWidth = imageHeight
        b.imageHeight = imageWidth
        if Self.turnsClockwise(to: target) {
            // 時計回り: 点 (x, y) → (H − y, x)
            b.aperture = Aperture(x: h - (a.y + a.height), y: a.x, width: a.height, height: a.width,
                                  cornerRadius: a.cornerRadius, cornerRadii: a.cornerRadii?.rotatedClockwise())
        } else {
            // 反時計回り: 点 (x, y) → (y, W − x)
            b.aperture = Aperture(x: a.y, y: w - (a.x + a.width), width: a.height, height: a.width,
                                  cornerRadius: a.cornerRadius, cornerRadii: a.cornerRadii?.rotatedCounterClockwise())
        }
        b.orientation = target
        return b
    }

    /// 縦 → 横は反時計回り（Apple の横向きベゼルはノッチが左側にある向き）、横 → 縦は時計回り。
    static func turnsClockwise(to target: BezelOrientation) -> Bool { target == .portrait }

    /// `turned(to:)` と同じ向きに画像を回すための、時計回りの 90° 単位の回転数。
    public func quarterTurns(to target: BezelOrientation) -> Int {
        effectiveOrientation == target ? 0 : (Self.turnsClockwise(to: target) ? 1 : 3)
    }

    public static func decode(from data: Data) throws -> Bezel {
        try JSONDecoder().decode(Bezel.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func load(from url: URL) throws -> Bezel {
        try decode(from: Data(contentsOf: url))
    }

    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }
}
