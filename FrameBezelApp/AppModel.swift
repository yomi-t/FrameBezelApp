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
    private static let previewMaxPixel = 1000.0

    @ObservationIgnored private let library = BezelLibrary()
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

    var selectedBezelFile: String? {
        didSet {
            bezelImage = selectedBezel.flatMap { try? library.loadImage(for: $0) }
            // 画面領域が変わると移動可能範囲も変わるので丸め直す（refreshPreview も内部で呼ばれる）
            setCrop(crop)
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
    var fit: FitMode = .fit {
        didSet { if oldValue != fit { refreshPreview() } }
    }
    /// 切り抜き（フィル時のみ有効）。スクショ単位の調整なのでプリセットには含めない
    private(set) var crop: ScreenCrop = .identity

    @ObservationIgnored private var bezelImage: CGImage?
    @ObservationIgnored private var isApplying = false

    init() {
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
        return ComposeSettings(background: background, fit: fit)
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
        return AspectMatcher.suggestionsAllowingRotation(
            screenshotWidth: screenshot.width, screenshotHeight: screenshot.height,
            from: bezels, excluding: selectedBezelFile)
    }

    /// 提案を適用する。回転が要る場合は現在の向きから時計回りに 90° 回す（逆なら回転ボタンで反転できる）。
    func apply(_ suggestion: AspectMatcher.Suggestion) {
        if suggestion.needsRotation { applyRotation(rotation.rotatedClockwise(), thenRefresh: false) }
        if suggestion.bezel.bezelFile == selectedBezelFile {
            setCrop(.identity)
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
        crop = .identity
        if thenRefresh { refreshPreview() }
    }

    private func setScreenshot(_ image: CGImage, name: String) {
        originalScreenshot = image
        screenshot = image
        rotation = .none
        screenshotName = name
        crop = .identity
        refreshPreview()
    }

    var screenshotAspect: Double? {
        screenshot.map { Double($0.width) / Double($0.height) }
    }

    /// 切り抜きを変更する。範囲外は画像が画面領域を埋める範囲に丸める。
    func setCrop(_ new: ScreenCrop) {
        guard let screenshot, let a = selectedBezel?.aperture else { crop = new; refreshPreview(); return }
        crop = new.clamped(screenshotWidth: Double(screenshot.width), screenshotHeight: Double(screenshot.height),
                           screenWidth: a.width, screenHeight: a.height)
        refreshPreview()
    }

    func resetCrop() { setCrop(.identity) }

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
                    if target == .bezel { self.addBezel(url: url) } else { self.loadScreenshot(url: url) }
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
            for b in bezels where thumbnails[b.bezelFile] == nil {
                thumbnails[b.bezelFile] = ImageFile.thumbnail(url: library.imageURL(for: b), maxPixel: 200)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func chooseBezelToAdd() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { addBezel(url: url) }
    }

    func addBezel(url: URL) {
        do {
            let bezel = try library.add(pngURL: url)
            reloadBezels()
            selectedBezelFile = bezel.bezelFile
            editingBezel = bezel // 検出結果の確認・微調整シートを開く
        } catch { errorMessage = "ベゼルを追加できません: \(error.localizedDescription)" }
    }

    func updateBezel(_ bezel: Bezel) {
        do {
            try library.update(bezel)
            reloadBezels()
            if bezel.bezelFile == selectedBezelFile { refreshPreview() }
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteBezel(_ bezel: Bezel) {
        do {
            try library.delete(bezel)
            thumbnails[bezel.bezelFile] = nil
            reloadBezels()
            if selectedBezelFile == bezel.bezelFile { selectedBezelFile = bezels.first?.bezelFile }
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
        fit = preset.settings.fit
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
        let full = Composer.outputSize(bezel: bezel)
        let scale = min(1, Self.previewMaxPixel / Double(max(full.width, full.height)))
        do {
            preview = try Composer.compose(screenshot: screenshot, bezel: bezel, bezelImage: bezelImage, settings: s, crop: crop, scale: scale)
        } catch { errorMessage = error.localizedDescription }
    }

    var suggestedFileName: String {
        let raw = "\(screenshotName.isEmpty ? "screenshot" : screenshotName)_\(selectedBezel?.name ?? "bezel").png"
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
            let image = try Composer.compose(screenshot: screenshot, bezel: bezel, bezelImage: bezelImage, settings: settings, crop: crop)
            try ImageFile.writePNG(image, to: url)
        } catch { errorMessage = "書き出しに失敗: \(error.localizedDescription)" }
    }
}
