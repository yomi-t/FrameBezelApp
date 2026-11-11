import Foundation

/// 画面領域。座標はベゼル PNG のピクセル単位で、原点は画像の左上（y は下向き）。
nonisolated public struct Aperture: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var cornerRadius: Double

    public init(x: Double, y: Double, width: Double, height: Double, cornerRadius: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
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
            b.aperture = Aperture(x: h - (a.y + a.height), y: a.x, width: a.height, height: a.width, cornerRadius: a.cornerRadius)
        } else {
            // 反時計回り: 点 (x, y) → (y, W − x)
            b.aperture = Aperture(x: a.y, y: w - (a.x + a.width), width: a.height, height: a.width, cornerRadius: a.cornerRadius)
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
