import Foundation

/// ベゼル + 背景（+ フィット）の名前付き組み合わせ。
public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    /// 定義の bezelFile。ベゼルが削除済みなら呼び出し時にベゼル選択は変えない。
    public var bezelFile: String?
    public var settings: ComposeSettings

    public var id: String { name }

    public init(name: String, bezelFile: String?, settings: ComposeSettings) {
        self.name = name
        self.bezelFile = bezelFile
        self.settings = settings
    }
}

/// `presets.json`（Application Support/FrameApp/ 直下）への保存。
public struct PresetStore {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("presets.json")
    }

    public func load() -> [Preset] {
        guard let data = try? Data(contentsOf: fileURL),
              let presets = try? JSONDecoder().decode([Preset].self, from: data) else { return [] }
        return presets
    }

    private func save(_ presets: [Preset]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(presets).write(to: fileURL, options: .atomic)
    }

    /// 同名があれば上書き。
    public func upsert(_ preset: Preset) throws -> [Preset] {
        var presets = load()
        if let i = presets.firstIndex(where: { $0.name == preset.name }) {
            presets[i] = preset
        } else {
            presets.append(preset)
        }
        try save(presets)
        return presets
    }

    public func delete(name: String) throws -> [Preset] {
        let presets = load().filter { $0.name != name }
        try save(presets)
        return presets
    }
}
