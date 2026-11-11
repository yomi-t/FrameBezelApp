import Foundation
import CoreGraphics

public enum BezelLibraryError: Error, LocalizedError {
    case notPNG
    case notFound

    public var errorDescription: String? {
        switch self {
        case .notPNG: return "ベゼルには PNG ファイルを指定してください"
        case .notFound: return "ベゼルが見つかりません"
        }
    }
}

/// Application Support 内のベゼル管理。1 ベゼル = `X.png` + `X.json`（定義）。
public final class BezelLibrary {
    /// 仕様 §4 の保存先名。
    public static let appDirectoryName = "FrameApp"
    private static let bundledMarker = ".bundled-installed"

    /// `…/Application Support/FrameApp`（プリセット等もここに置く）
    public let appDirectory: URL
    public var bezelsDirectory: URL { appDirectory.appendingPathComponent("Bezels", isDirectory: true) }

    private let fm = FileManager.default

    public init(appDirectory: URL? = nil) {
        if let appDirectory {
            self.appDirectory = appDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.appDirectory = base.appendingPathComponent(Self.appDirectoryName, isDirectory: true)
        }
    }

    private func ensureDirectories() throws {
        try fm.createDirectory(at: bezelsDirectory, withIntermediateDirectories: true)
    }

    private func jsonURL(for bezel: Bezel) -> URL {
        let base = (bezel.bezelFile as NSString).deletingPathExtension
        return bezelsDirectory.appendingPathComponent(base + ".json")
    }

    public func imageURL(for bezel: Bezel) -> URL {
        bezelsDirectory.appendingPathComponent(bezel.bezelFile)
    }

    public func loadImage(for bezel: Bezel) throws -> CGImage {
        try ImageFile.load(url: imageURL(for: bezel))
    }

    /// 一覧。Application Support 側の JSON だけを見る（仕様 §4）。PNG が無い定義は除外。
    public func list() throws -> [Bezel] {
        try ensureDirectories()
        let files = try fm.contentsOfDirectory(at: bezelsDirectory, includingPropertiesForKeys: nil)
        var result: [Bezel] = []
        for url in files where url.pathExtension.lowercased() == "json" {
            guard let bezel = try? Bezel.load(from: url),
                  fm.fileExists(atPath: imageURL(for: bezel).path) else { continue }
            result.append(bezel)
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 追加 = コピー + 検出 + JSON 保存。検出失敗時はコピーを残さない。
    @discardableResult
    public func add(pngURL: URL, name: String? = nil) throws -> Bezel {
        guard pngURL.pathExtension.lowercased() == "png" else { throw BezelLibraryError.notPNG }
        try ensureDirectories()

        let fileName = uniqueFileName(for: pngURL.lastPathComponent)
        let dest = bezelsDirectory.appendingPathComponent(fileName)
        try fm.copyItem(at: pngURL, to: dest)
        do {
            return try registerCopied(fileName: fileName, name: name)
        } catch {
            try? fm.removeItem(at: dest)
            throw error
        }
    }

    /// bezelsDirectory 内にある PNG を検出して JSON を書く。
    private func registerCopied(fileName: String, name: String?) throws -> Bezel {
        let image = try ImageFile.load(url: bezelsDirectory.appendingPathComponent(fileName))
        let aperture = try BezelDetector.detect(image: image)
        let bezel = Bezel(name: name ?? Self.defaultName(for: fileName), bezelFile: fileName,
                          imageWidth: image.width, imageHeight: image.height, aperture: aperture)
        try bezel.write(to: jsonURL(for: bezel))
        return bezel
    }

    /// 手動微調整・名前変更の保存。
    public func update(_ bezel: Bezel) throws {
        guard fm.fileExists(atPath: imageURL(for: bezel).path) else { throw BezelLibraryError.notFound }
        try bezel.write(to: jsonURL(for: bezel))
    }

    public func rename(_ bezel: Bezel, to newName: String) throws {
        var updated = bezel
        updated.name = newName
        try update(updated)
    }

    public func delete(_ bezel: Bezel) throws {
        try? fm.removeItem(at: jsonURL(for: bezel))
        try fm.removeItem(at: imageURL(for: bezel))
    }

    /// 初回起動時のみ、バンドル同梱のベゼルを Application Support 側へコピーする。
    /// 以後はユーザーが削除したものが復活しないよう、マーカーで 1 回きりにする。
    /// 同梱フォルダに PNG だけがあれば検出して JSON を作り、JSON もあればそれを使う。
    public func installBundledIfNeeded(from bundledDirectory: URL?) throws {
        try ensureDirectories()
        let marker = appDirectory.appendingPathComponent(Self.bundledMarker)
        guard !fm.fileExists(atPath: marker.path) else { return }
        defer { fm.createFile(atPath: marker.path, contents: Data()) }
        guard let bundledDirectory,
              let files = try? fm.contentsOfDirectory(at: bundledDirectory, includingPropertiesForKeys: nil)
        else { return }

        for png in files where png.pathExtension.lowercased() == "png" {
            let fileName = uniqueFileName(for: png.lastPathComponent)
            let dest = bezelsDirectory.appendingPathComponent(fileName)
            guard (try? fm.copyItem(at: png, to: dest)) != nil else { continue }

            let bundledJSON = png.deletingPathExtension().appendingPathExtension("json")
            if fileName == png.lastPathComponent,
               var bezel = try? Bezel.load(from: bundledJSON) {
                bezel.bezelFile = fileName
                try? bezel.write(to: jsonURL(for: bezel))
            } else if (try? registerCopied(fileName: fileName, name: nil)) == nil {
                try? fm.removeItem(at: dest)
            }
        }
    }

    private func uniqueFileName(for original: String) -> String {
        let base = (original as NSString).deletingPathExtension
        let ext = (original as NSString).pathExtension
        var candidate = original
        var n = 2
        while fm.fileExists(atPath: bezelsDirectory.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(n).\(ext)"
            n += 1
        }
        return candidate
    }

    /// "Bezel-iPhone-17.png" → "iPhone 17"
    static func defaultName(for fileName: String) -> String {
        var base = (fileName as NSString).deletingPathExtension
        if base.hasPrefix("Bezel-") { base.removeFirst("Bezel-".count) }
        return base.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    }
}
