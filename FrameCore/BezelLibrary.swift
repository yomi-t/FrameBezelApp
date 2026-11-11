import Foundation
import CoreGraphics

nonisolated public enum BezelLibraryError: Error, LocalizedError {
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
nonisolated public final class BezelLibrary: Sendable {
    /// 仕様 §4 の保存先名。
    public static let appDirectoryName = "FrameApp"
    private static let bundledMarker = ".bundled-installed"

    /// `…/Application Support/FrameApp`（プリセット等もここに置く）
    public let appDirectory: URL
    public var bezelsDirectory: URL { appDirectory.appendingPathComponent("Bezels", isDirectory: true) }

    private var fm: FileManager { .default }

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
        return result.sorted { $0.modelName.localizedStandardCompare($1.modelName) == .orderedAscending }
    }

    /// 追加 = コピー + 検出 + JSON 保存。検出失敗時はコピーを残さない。
    /// ファイル名が `機種 - 色 - Portrait` 形式なら機種・向き・色も読み取る。
    @discardableResult
    public func add(pngURL: URL, name: String? = nil, meta: BezelMeta? = nil) throws -> Bezel {
        guard pngURL.pathExtension.lowercased() == "png" else { throw BezelLibraryError.notPNG }
        try ensureDirectories()

        let fileName = uniqueFileName(for: pngURL.lastPathComponent)
        let dest = bezelsDirectory.appendingPathComponent(fileName)
        try fm.copyItem(at: pngURL, to: dest)
        do {
            let meta = meta ?? BezelNaming.parse(fileName: pngURL.lastPathComponent, folderName: nil)
            return try registerCopied(fileName: fileName, name: name, meta: meta)
        } catch {
            try? fm.removeItem(at: dest)
            throw error
        }
    }

    /// bezelsDirectory 内にある PNG を検出して JSON を書く。
    private func registerCopied(fileName: String, name: String?, meta: BezelMeta? = nil) throws -> Bezel {
        let image = try ImageFile.load(url: bezelsDirectory.appendingPathComponent(fileName))
        let aperture = try BezelDetector.detect(image: image)
        let displayName: String
        if let name {
            displayName = name
        } else if let model = meta?.model {
            displayName = model // 色は別の項目。名前は機種の正式名称だけにする
        } else {
            displayName = Self.defaultName(for: fileName)
        }
        let bezel = Bezel(name: displayName, bezelFile: fileName,
                          imageWidth: image.width, imageHeight: image.height, aperture: aperture,
                          model: meta?.model, orientation: meta?.orientation, color: meta?.color, variant: meta?.variant)
        try bezel.write(to: jsonURL(for: bezel))
        return bezel
    }

    // MARK: フォルダ取り込み

    nonisolated public struct ImportResult: Sendable {
        public var added: [Bezel] = []
        /// 同じ機種・向き・色が既にあるためスキップした数
        public var skippedDuplicates = 0
        /// 取り込めなかったファイル（`ファイル名: 理由`）
        public var failed: [String] = []
        /// PNG が 1 枚も無かったフォルダ
        public var emptyFolders: [String] = []
    }

    /// Apple 配布のフォルダ（機種名フォルダ、または機種フォルダを束ねた親フォルダ）を丸ごと取り込む。
    /// 機種はフォルダ名、色と向きはファイル名から決める。向きがファイル名に無ければ画面領域の縦横から推定する。
    public func importFolder(_ folder: URL) -> ImportResult {
        var result = ImportResult()
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: keys,
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            result.failed.append("\(folder.lastPathComponent): フォルダを開けません")
            return result
        }
        var pngs: [URL] = []
        for case let url as URL in walker {
            guard url.pathExtension.lowercased() == "png",
                  (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true else { continue }
            pngs.append(url)
        }
        if pngs.isEmpty { result.emptyFolders.append(folder.lastPathComponent); return result }

        var existing = (try? list()) ?? []
        for png in pngs.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            let meta = BezelNaming.parse(fileName: png.lastPathComponent, folderName: Self.modelFolderName(for: png))
            do {
                let bezel = try addDetecting(png: png, meta: meta, existing: existing)
                if let bezel {
                    result.added.append(bezel)
                    existing.append(bezel)
                } else {
                    result.skippedDuplicates += 1
                }
            } catch {
                result.failed.append("\(png.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// 重複なら nil。向きが未指定なら検出した画面領域から補う。
    private func addDetecting(png: URL, meta: BezelMeta, existing: [Bezel]) throws -> Bezel? {
        if let orientation = meta.orientation,
           existing.contains(where: { $0.model == meta.model && $0.color == meta.color && $0.variant == meta.variant && $0.orientation == orientation }) {
            return nil
        }
        try ensureDirectories()
        let fileName = uniqueFileName(for: png.lastPathComponent)
        let dest = bezelsDirectory.appendingPathComponent(fileName)
        try fm.copyItem(at: png, to: dest)
        do {
            var bezel = try registerCopied(fileName: fileName, name: nil, meta: meta)
            if bezel.orientation == nil {
                bezel.orientation = bezel.aperture.width > bezel.aperture.height ? .landscape : .portrait
                if existing.contains(where: { $0.model == bezel.model && $0.color == bezel.color && $0.variant == bezel.variant && $0.orientation == bezel.orientation }) {
                    try? fm.removeItem(at: dest)
                    try? fm.removeItem(at: jsonURL(for: bezel))
                    return nil
                }
                try bezel.write(to: jsonURL(for: bezel))
            }
            return bezel
        } catch {
            try? fm.removeItem(at: dest)
            throw error
        }
    }

    /// PNG を直接含むフォルダ名。`Portrait` / `Landscape` / `PNG` のような機種名でないフォルダは飛ばして 1 つ上を使う。
    /// 機種名はここではなくファイル名を優先して決める（`BezelNaming.parse`）。
    private static func modelFolderName(for png: URL) -> String? {
        var dir = png.deletingLastPathComponent()
        while BezelNaming.genericFolderNames.contains(dir.lastPathComponent.lowercased()) {
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }
            dir = parent
        }
        let name = dir.lastPathComponent
        return name.isEmpty ? nil : name
    }

    /// 手動微調整・名前変更の保存。
    public func update(_ bezel: Bezel) throws {
        guard fm.fileExists(atPath: imageURL(for: bezel).path) else { throw BezelLibraryError.notFound }
        try bezel.write(to: jsonURL(for: bezel))
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

    /// "Bezel-iPhone-17.png" → "iPhone 17"（接頭辞の Bezel は付けない）
    static func defaultName(for fileName: String) -> String {
        let base = BezelNaming.officialName((fileName as NSString).deletingPathExtension)
        return base.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    }
}
