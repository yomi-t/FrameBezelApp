import Foundation

/// 画面領域。座標はベゼル PNG のピクセル単位で、原点は画像の左上（y は下向き）。
public struct Aperture: Codable, Equatable, Sendable {
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

/// ベゼル定義（仕様 §7 の JSON 形式と 1:1 対応）。
public struct Bezel: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var bezelFile: String
    public var imageWidth: Int
    public var imageHeight: Int
    public var aperture: Aperture

    public var id: String { bezelFile }

    public init(name: String, bezelFile: String, imageWidth: Int, imageHeight: Int, aperture: Aperture) {
        self.name = name
        self.bezelFile = bezelFile
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.aperture = aperture
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
