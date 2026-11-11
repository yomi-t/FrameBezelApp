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

    public var id: String { bezelFile }

    public init(name: String, bezelFile: String, imageWidth: Int, imageHeight: Int, aperture: Aperture,
                model: String? = nil, orientation: BezelOrientation? = nil, color: String? = nil) {
        self.name = name
        self.bezelFile = bezelFile
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.aperture = aperture
        self.model = model
        self.orientation = orientation
        self.color = color
    }

    public var modelName: String { model ?? name }

    /// 向きが未設定の旧データは、画面領域の縦横から推定する。
    public var effectiveOrientation: BezelOrientation {
        orientation ?? (aperture.width > aperture.height ? .landscape : .portrait)
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
