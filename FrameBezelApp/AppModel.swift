import SwiftUI
import AppKit
import Foundation
import CoreGraphics
import Observation
import UniformTypeIdentifiers

enum BackgroundKind: String, CaseIterable, Identifiable {
    case solid = "単色"
    case gradient = "グラデーション"
    case transparent = "透明"
    var id: String { rawValue }
    /// セグメント表示用の短い名前（インスペクタの幅に収めるため）
    var shortName: String { self == .gradient ? "グラデ" : rawValue }
}

enum DropTarget { case screenshot, bezel }

extension RGBAColor {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent),
                  b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

@MainActor
@Observable
final class AppModel {
    private static let lastExportDirKey = "lastExportDirectory"
    private static let exportSizeKey = "exportSizeID"
    private static let previewMaxPixel = 2000.0

    @ObservationIgnored private let library: BezelLibrary
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let presetStore: PresetStore

    private(set) var bezels: [Bezel] = []
    private(set) var thumbnails: [String: CGImage] = [:]
    private(set) var presets: [Preset] = []
    /// 読み込んだままのスクショ（回転前）
    private(set) var originalScreenshot: CGImage?
    /// 回転を反映したスクショ。判定・提案・プレビュー・書き出しはすべてこれを使う
    private(set) var screenshot: CGImage?
    private(set) var rotation: Rotation = .none
    private(set) var screenshotName = ""
    private(set) var preview: CGImage?
    var errorMessage: String?
    var editingBezel: Bezel?
    /// 書き出しサイズ（App Store Connect 提出用）。nil はベゼル PNG の元サイズ
    var exportSizeID: String? {
        didSet {
            defaults.set(exportSizeID, forKey: Self.exportSizeKey)
            if oldValue != exportSizeID { refreshPreview() }
        }
    }
    var exportSize: AppStoreSize? { AppStoreSize.find(id: exportSizeID) }
    /// 書き出す画像の寸法（App Store 提出サイズ、無ければベゼル元サイズ）
    var exportCanvas: (width: Int, height: Int)? {
        guard let bezel = selectedBezel else { return nil }
        return exportSize?.canvas(for: bezel.effectiveOrientation) ?? Composer.outputSize(bezel: bezel)
    }
    /// フォルダ取り込み中（UI にスピナーを出す）
    private(set) var isImporting = false
    /// 取り込み結果の概要（アラート表示用）
    var importSummary: String?

    var selectedBezelFile: String? {
        didSet {
            bezelImage = selectedBezel.flatMap { try? library.loadImage(for: $0) }
            // 色違いなど画面領域が同じなら調整を引き継ぎ、違うなら「収める」に戻す（refreshPreview も内部で呼ばれる）
            let old = bezels.first { $0.bezelFile == oldValue }?.aperture
            let new = selectedBezel?.aperture
            let sameScreen = old != nil && new != nil && old?.width == new?.width && old?.height == new?.height
            setCrop(sameScreen ? crop : .fit)
        }
    }
    var backgroundKind: BackgroundKind = .transparent {
        didSet { if oldValue != backgroundKind { refreshPreview() } }
    }
    var solidColor: Color = Color(white: 0.1) {
        didSet { if oldValue != solidColor { refreshPreview() } }
    }
    var gradientStart: Color = Color(red: 0.35, green: 0.4, blue: 0.95) {
        didSet { if oldValue != gradientStart { refreshPreview() } }
    }
    var gradientEnd: Color = Color(red: 0.7, green: 0.3, blue: 0.85) {
        didSet { if oldValue != gradientEnd { refreshPreview() } }
    }
    var gradientAngle: Double = 90 {
        didSet { if oldValue != gradientAngle { refreshPreview() } }
    }
    /// 拡大率と位置。スクショ単位の調整なのでプリセットには含めない。常に `clamp` 済みの値を持つ
    private(set) var crop: ScreenCrop = .fill

    @ObservationIgnored private var bezelImage: CGImage?
    @ObservationIgnored private var isApplying = false

    /// テストでは一時フォルダのライブラリと専用の UserDefaults を渡し、本物の保存先に触れないようにする。
    init(library: BezelLibrary = BezelLibrary(), defaults: UserDefaults = .standard) {
        self.library = library
        self.defaults = defaults
        exportSizeID = defaults.string(forKey: Self.exportSizeKey)
        presetStore = PresetStore(directory: library.appDirectory)
        do {
            try library.installBundledIfNeeded(from: Bundle.main.url(forResource: "Bezels", withExtension: nil))
        } catch {
            errorMessage = "同梱ベゼルのコピーに失敗: \(error.localizedDescription)"
        }
        reloadBezels()
        presets = presetStore.load()
        selectedBezelFile = bezels.first?.bezelFile
        // init 中は didSet が走らないため、選択中ベゼルの画像はここで読み込む
        bezelImage = selectedBezel.flatMap { try? library.loadImage(for: $0) }
    }

    var selectedBezel: Bezel? { bezels.first { $0.bezelFile == selectedBezelFile } }

    var settings: ComposeSettings {
        let background: BackgroundStyle
        switch backgroundKind {
        case .solid: background = .solid(RGBAColor(solidColor))
        case .gradient:
            background = .gradient(start: RGBAColor(gradientStart), end: RGBAColor(gradientEnd), angleDegrees: gradientAngle)
        case .transparent: background = .transparent
        }
        return ComposeSettings(background: background)
    }

    // MARK: 縦横比

    /// スクショと選択中ベゼルの縦横比が許容差内か。判定できない（未読込など）ときは nil。
    var aspectMatches: Bool? {
        guard let screenshot, let bezel = selectedBezel else { return nil }
        return AspectMatcher.matches(screenshotWidth: screenshot.width, screenshotHeight: screenshot.height, aperture: bezel.aperture)
    }

    /// 不一致のときに提案する、画面領域の縦横比が合うベゼル。90° 回転すれば合うものも含む（回転は提案のみで自動適用しない）。
    var suggestedBezels: [AspectMatcher.Suggestion] {
        guard let screenshot, aspectMatches == false else { return [] }
        let all = AspectMatcher.suggestionsAllowingRotation(
            screenshotWidth: screenshot.width, screenshotHeight: screenshot.height,
            from: bezels, excluding: selectedBezelFile)
        // 色違いが大量に並ばないよう、機種×向き×回転の要否ごとに 1 件へ絞る（選択中の色を優先）
        let preferredColor = selectedBezel?.color
        var result: [AspectMatcher.Suggestion] = []
        for s in all {
            let key = { (x: AspectMatcher.Suggestion) in "\(x.bezel.modelName)|\(x.bezel.effectiveOrientation)|\(x.needsRotation)" }
            if let i = result.firstIndex(where: { key($0) == key(s) }) {
                if result[i].bezel.color != preferredColor, s.bezel.color == preferredColor { result[i] = s }
            } else {
                result.append(s)
            }
        }
        return result
    }

    // MARK: 機種 → 向き・色

    var modelGroups: [BezelModelGroup] { BezelCatalog.groups(bezels) }
    var selectedGroup: BezelModelGroup? {
        guard let name = selectedBezel?.modelName else { return nil }
        return modelGroups.first { $0.model == name }
    }

    /// 機種を選ぶ。今の向き・色があれば引き継ぐ。
    func selectModel(_ group: BezelModelGroup) {
        let current = selectedBezel
        if let screenshot {
            // スクショがあるときは、縦横比がよく合う向きを既定にする
            selectedBezelFile = group.bestMatch(screenshotWidth: screenshot.width, screenshotHeight: screenshot.height,
                                                color: current?.color).bezelFile
        } else {
            selectedBezelFile = group.pick(orientation: current?.effectiveOrientation, color: current?.color).bezelFile
        }
    }

    func selectOrientation(_ orientation: BezelOrientation) {
        guard let group = selectedGroup else { return }
        selectedBezelFile = group.pick(orientation: orientation, color: selectedBezel?.color).bezelFile
    }

    func selectColor(_ color: String) {
        guard let group = selectedGroup, let current = selectedBezel else { return }
        selectedBezelFile = group.pick(orientation: current.effectiveOrientation, color: color).bezelFile
    }

    /// 提案を適用する。回転が要る場合は現在の向きから時計回りに 90° 回す（逆なら回転ボタンで反転できる）。
    func apply(_ suggestion: AspectMatcher.Suggestion) {
        if suggestion.needsRotation { applyRotation(rotation.rotatedClockwise(), thenRefresh: false) }
        if suggestion.bezel.bezelFile == selectedBezelFile {
            setCrop(.fit)
        } else {
            selectedBezelFile = suggestion.bezel.bezelFile // didSet でプレビュー更新
        }
    }

    // MARK: 回転

    func rotateClockwise() { applyRotation(rotation.rotatedClockwise(), thenRefresh: true) }
    func rotateCounterClockwise() { applyRotation(rotation.rotatedCounterClockwise(), thenRefresh: true) }

    private func applyRotation(_ new: Rotation, thenRefresh: Bool) {
        guard let originalScreenshot else { return }
        rotation = new
        screenshot = ImageRotation.rotate(originalScreenshot, new) ?? originalScreenshot
        // 向きが変わると切り抜きの基準も変わるのでリセット
        crop = clamp(.fit)
        if thenRefresh { refreshPreview() }
    }

    private func setScreenshot(_ image: CGImage, name: String) {
        originalScreenshot = image
        screenshot = image
        rotation = .none
        screenshotName = name
        crop = clamp(.fit)
        // 選択中の機種に別の向きがあり、そちらのほうが縦横比に合うなら向きを切り替える（色は維持）
        if let group = selectedGroup, group.orientations.count > 1,
           let current = selectedBezel {
            let best = group.bestMatch(screenshotWidth: image.width, screenshotHeight: image.height, color: current.color)
            if best.bezelFile != current.bezelFile {
                selectedBezelFile = best.bezelFile // didSet でプレビュー更新
                return
            }
        }
        refreshPreview()
    }

    var screenshotAspect: Double? {
        screenshot.map { Double($0.width) / Double($0.height) }
    }

    /// 切り抜きを変更する。範囲外は画像が画面領域を埋める範囲に丸める。
    /// 現在のスクショと画面領域に合わせて zoom・移動量を有効範囲へ丸める。
    private func clamp(_ new: ScreenCrop) -> ScreenCrop {
        guard let screenshot, let a = selectedBezel?.aperture else { return ScreenCrop(zoom: max(new.zoom, 1)) }
        return new.clamped(screenshotWidth: Double(screenshot.width), screenshotHeight: Double(screenshot.height),
                           screenWidth: a.width, screenHeight: a.height)
    }

    func setCrop(_ new: ScreenCrop) {
        crop = clamp(new)
        refreshPreview()
    }

    /// ドラッグ移動用。有効範囲に丸めたあと、画像の辺が画面領域の辺に近ければ吸着させる。吸着したら true。
    @discardableResult
    func moveCrop(to new: ScreenCrop, snapThreshold: Double) -> Bool {
        var result = (crop: clamp(new), snapped: false)
        if let screenshot, let a = selectedBezel?.aperture {
            result = result.crop.snappedPosition(screenshotWidth: Double(screenshot.width),
                                                 screenshotHeight: Double(screenshot.height),
                                                 aperture: a, threshold: snapThreshold)
        }
        crop = result.crop
        refreshPreview()
        return result.snapped
    }

    // MARK: サイズ・位置の数値入力（単位は書き出し PNG の px、原点は画面領域の左上）

    var imageFrame: CGRect? {
        guard let screenshot, let a = selectedBezel?.aperture else { return nil }
        let r = crop.imageRect(screenshotWidth: Double(screenshot.width), screenshotHeight: Double(screenshot.height), aperture: a)
        return r.offsetBy(dx: -a.x, dy: -a.y)
    }

    func setImageWidth(_ width: Double) {
        guard let screenshot, let a = selectedBezel?.aperture else { return }
        setCrop(crop.withImageWidth(width, screenshotWidth: Double(screenshot.width), screenshotHeight: Double(screenshot.height), aperture: a))
    }

    func setImageHeight(_ height: Double) {
        guard let screenshot, let a = selectedBezel?.aperture else { return }
        setCrop(crop.withImageHeight(height, screenshotWidth: Double(screenshot.width), screenshotHeight: Double(screenshot.height), aperture: a))
    }

    func setImageOrigin(x: Double? = nil, y: Double? = nil) {
        guard let screenshot, let a = selectedBezel?.aperture, let frame = imageFrame else { return }
        setCrop(crop.withImageOrigin(x: x ?? frame.minX, y: y ?? frame.minY,
                                     screenshotWidth: Double(screenshot.width), screenshotHeight: Double(screenshot.height), aperture: a))
    }

    /// 収める：全体が画面領域に入る大きさにする（状態は持たず、拡大率・位置を初期化するだけ）
    func fitToScreen() { setCrop(.fit) }
    /// 埋める：画面領域をすき間なく埋める大きさにする
    func fillScreen() { setCrop(.fill) }

    // MARK: 入力

    func loadScreenshot(url: URL) {
        do {
            setScreenshot(try ImageFile.load(url: url), name: url.deletingPathExtension().lastPathComponent)
        } catch { errorMessage = error.localizedDescription }
    }

    func loadScreenshot(data: Data, name: String) {
        do {
            setScreenshot(try ImageFile.load(data: data), name: name)
        } catch { errorMessage = error.localizedDescription }
    }

    func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let url = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first {
            loadScreenshot(url: url)
        } else if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            loadScreenshot(data: data, name: "Pasted")
        } else {
            errorMessage = "クリップボードに画像がありません"
        }
    }

    /// ドロップ / ペーストの NSItemProvider を処理する。
    func handle(providers: [NSItemProvider], target: DropTarget) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if target == .bezel { self.addBezelOrFolder(urls: [url]) } else { self.loadScreenshot(url: url) }
                }
            }
            return true
        }
        if target == .screenshot, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in self.loadScreenshot(data: data, name: "Pasted") }
            }
            return true
        }
        return false
    }

    func chooseScreenshot() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { loadScreenshot(url: url) }
    }

    // MARK: ベゼル管理

    private func reloadBezels() {
        do {
            bezels = try library.list()
            // サムネイルは機種ごとの代表だけ（色違いまで全部読むと取り込み後に重くなる）
            for b in BezelCatalog.groups(bezels).map(\.representative) where thumbnails[b.bezelFile] == nil {
                thumbnails[b.bezelFile] = ImageFile.thumbnail(url: library.imageURL(for: b), maxPixel: 200)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// PNG 1 枚、または Apple 配布のフォルダ（複数可）を選んで追加する。
    func chooseBezelToAdd() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .folder]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "ベゼルの PNG、または機種名のフォルダ（複数可）を選んでください"
        if panel.runModal() == .OK { addBezelOrFolder(urls: panel.urls) }
    }

    /// フォルダはまとめて取り込み（バックグラウンド）、PNG 単体は従来どおり追加して確認シートを開く。
    func addBezelOrFolder(urls: [URL]) {
        let isDir = { (u: URL) in (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let folders = urls.filter(isDir)
        let files = urls.filter { !isDir($0) }
        if files.count == 1, folders.isEmpty {
            addBezel(url: files[0])
            return
        }
        for f in files { addBezel(url: f, openEditor: false) }
        if !folders.isEmpty { importBezelFolders(folders) }
    }

    private func importBezelFolders(_ folders: [URL]) {
        guard !isImporting else { return }
        isImporting = true
        let library = library
        Task {
            // 画像のデコードと検出が重いのでメインスレッド外で実行する
            let results = await Task.detached { folders.map { library.importFolder($0) } }.value
            var total = BezelLibrary.ImportResult()
            for r in results {
                total.added += r.added
                total.skippedDuplicates += r.skippedDuplicates
                total.failed += r.failed
                total.emptyFolders += r.emptyFolders
            }
            reloadBezels()
            if let first = total.added.first {
                let group = modelGroups.first { $0.model == first.modelName }
                selectedBezelFile = (group?.pick(orientation: .portrait, color: nil) ?? first).bezelFile
            }
            isImporting = false
            importSummary = Self.summary(of: total)
        }
    }

    private static func summary(of r: BezelLibrary.ImportResult) -> String {
        var lines = ["\(r.added.count) 枚のベゼルを追加しました（\(Set(r.added.map(\.modelName)).count) 機種）"]
        if r.skippedDuplicates > 0 { lines.append("登録済みのためスキップ: \(r.skippedDuplicates) 枚") }
        if !r.emptyFolders.isEmpty { lines.append("PNG が見つからないフォルダ: " + r.emptyFolders.joined(separator: "、")) }
        if !r.failed.isEmpty {
            lines.append("取り込めなかったファイル: \(r.failed.count) 枚")
            lines.append(contentsOf: r.failed.prefix(5))
            if r.failed.count > 5 { lines.append("…ほか \(r.failed.count - 5) 件") }
        }
        return lines.joined(separator: "\n")
    }

    func addBezel(url: URL, openEditor: Bool = true) {
        do {
            let bezel = try library.add(pngURL: url)
            reloadBezels()
            selectedBezelFile = bezel.bezelFile
            if openEditor { editingBezel = bezel } // 検出結果の確認・微調整シートを開く
        } catch { errorMessage = "ベゼルを追加できません: \(error.localizedDescription)" }
    }

    func updateBezel(_ bezel: Bezel) {
        do {
            try library.update(bezel)
            reloadBezels()
            if bezel.bezelFile == selectedBezelFile { refreshPreview() }
        } catch { errorMessage = error.localizedDescription }
    }

    /// 機種に属するベゼル（向き・色違い）をすべて削除する。
    func deleteModel(_ group: BezelModelGroup) {
        do {
            for b in group.bezels {
                try library.delete(b)
                thumbnails[b.bezelFile] = nil
            }
            reloadBezels()
            if selectedBezel == nil { selectedBezelFile = bezels.first?.bezelFile }
        } catch { errorMessage = error.localizedDescription }
    }

    func bezelImage(for bezel: Bezel) -> CGImage? { try? library.loadImage(for: bezel) }

    // MARK: プリセット

    func savePreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            presets = try presetStore.upsert(Preset(name: trimmed, bezelFile: selectedBezelFile, settings: settings))
        } catch { errorMessage = error.localizedDescription }
    }

    func apply(_ preset: Preset) {
        isApplying = true
        switch preset.settings.background {
        case .solid(let c):
            backgroundKind = .solid
            solidColor = c.color
        case .gradient(let s, let e, let angle):
            backgroundKind = .gradient
            gradientStart = s.color
            gradientEnd = e.color
            gradientAngle = angle
        case .transparent:
            backgroundKind = .transparent
        }
        isApplying = false
        if let file = preset.bezelFile, bezels.contains(where: { $0.bezelFile == file }) {
            selectedBezelFile = file // didSet でプレビュー更新
        } else {
            refreshPreview()
        }
    }

    func deletePreset(_ preset: Preset) {
        do { presets = try presetStore.delete(name: preset.name) } catch { errorMessage = error.localizedDescription }
    }

    // MARK: 合成・書き出し

    private func refreshPreview() {
        guard !isApplying else { return }
        guard let screenshot, let bezel = selectedBezel, let bezelImage else {
            // 既に nil のときは代入しない（は同値でも通知し、ビュー更新中だと警告になる）
            if preview != nil { preview = nil }
            return
        }
        let s = settings
        let full = exportCanvas ?? Composer.outputSize(bezel: bezel)
        let scale = min(1, Self.previewMaxPixel / Double(max(full.width, full.height)))
        do {
            // 書き出しサイズを選んでいるときは、余白や背景込みの最終画像をそのままプレビューする
            if exportSize != nil {
                let canvas = (width: max(1, Int((Double(full.width) * scale).rounded())),
                              height: max(1, Int((Double(full.height) * scale).rounded())))
                preview = try Composer.composeFitted(screenshot: screenshot, bezel: bezel, bezelImage: bezelImage,
                                                     settings: s, crop: crop, canvas: canvas)
                return
            }
            preview = try Composer.compose(screenshot: screenshot, bezel: bezel, bezelImage: bezelImage, settings: s, crop: crop, scale: scale)
        } catch { errorMessage = error.localizedDescription }
    }

    var suggestedFileName: String {
        let sizeSuffix = exportCanvas.map { exportSize == nil ? "" : "_\($0.width)x\($0.height)" } ?? ""
        let raw = "\(screenshotName.isEmpty ? "screenshot" : screenshotName)_\(selectedBezel?.name ?? "bezel")\(sizeSuffix).png"
        return raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    func exportPNG() {
        guard let screenshot, let bezel = selectedBezel, let bezelImage else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedFileName
        if let dir = UserDefaults.standard.string(forKey: Self.lastExportDirKey) {
            panel.directoryURL = URL(fileURLWithPath: dir, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: Self.lastExportDirKey)
        do {
            let image: CGImage
            if let canvas = exportSize.map({ $0.canvas(for: bezel.effectiveOrientation) }) {
                image = try Composer.composeFitted(screenshot: screenshot, bezel: bezel, bezelImage: bezelImage,
                                                   settings: settings, crop: crop, canvas: canvas)
            } else {
                image = try Composer.compose(screenshot: screenshot, bezel: bezel, bezelImage: bezelImage, settings: settings, crop: crop)
            }
            try ImageFile.writePNG(image, to: url)
        } catch { errorMessage = "書き出しに失敗: \(error.localizedDescription)" }
    }
}
