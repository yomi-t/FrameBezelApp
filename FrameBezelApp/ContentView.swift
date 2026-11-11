import SwiftUI
import Foundation
import CoreGraphics
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var isTargeted = false
    @State private var isBezelTargeted = false
    @State private var bezelToDelete: Bezel?
    @State private var showSavePreset = false
    @State private var presetName = ""
    @State private var dragStartCrop: ScreenCrop?

    var body: some View {
        HStack(spacing: 0) {
            previewPane
            Divider()
            settingsPanel.frame(width: 340)
        }
        .sheet(item: $model.editingBezel) { bezel in
            BezelEditorView(bezel: bezel).environmentObject(model)
        }
        .alert("エラー", isPresented: Binding(get: { model.errorMessage != nil },
                                              set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("このベゼルを削除しますか？", isPresented: Binding(get: { bezelToDelete != nil },
                                                                  set: { if !$0 { bezelToDelete = nil } })) {
            Button("削除", role: .destructive) { if let b = bezelToDelete { model.deleteBezel(b) } }
        }
        .alert("プリセットを保存", isPresented: $showSavePreset) {
            TextField("名前", text: $presetName)
            Button("保存") { model.savePreset(name: presetName) }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("現在のベゼル・背景を保存します（同名は上書き）") }
    }

    // MARK: 左：プレビュー（ドロップ受け口）

    private var previewPane: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if let preview = model.preview {
                GeometryReader { geo in
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .gesture(cropDragGesture(in: geo.size, preview: preview))
                }
                .padding(16)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 40))
                    Text(model.screenshot == nil ? "スクリーンショットをここにドロップ" : "ベゼルを選択してください")
                    Text("または ⌘V でペースト / 右のボタンでファイル選択").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            if isTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3).padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { model.handle(providers: $0, target: .screenshot) }
        .onPasteCommand(of: [.fileURL, .image]) { _ = model.handle(providers: $0, target: .screenshot) }
    }

    /// フィル時のみ、プレビューのドラッグでスクショの表示位置を動かす。
    /// 画面上の移動量 → 合成座標（ベゼル等倍）→ 画面領域幅/高さで正規化。
    private func cropDragGesture(in available: CGSize, preview: CGImage) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard model.fit == .fill, let bezel = model.selectedBezel else { return }
                if dragStartCrop == nil { dragStartCrop = model.crop }
                guard let start = dragStartCrop else { return }
                let logicalW = Double(bezel.imageWidth)
                let displayedW = min(available.width, available.height * Double(preview.width) / Double(preview.height))
                let pointsPerPixel = displayedW / logicalW
                guard pointsPerPixel > 0 else { return }
                var c = start
                c.offsetX += value.translation.width / pointsPerPixel / bezel.aperture.width
                c.offsetY += value.translation.height / pointsPerPixel / bezel.aperture.height
                model.setCrop(c)
            }
            .onEnded { _ in dragStartCrop = nil }
    }

    // MARK: 右：設定パネル

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("入力") {
                    HStack {
                        Button("ファイルを選択…") { model.chooseScreenshot() }
                        Button("ペースト") { model.pasteFromClipboard() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                bezelSection
                orientationSection
                aspectSection
                backgroundSection
                GroupBox("フィット") {
                    VStack(alignment: .leading) {
                        Picker("フィット", selection: $model.fit) {
                            Text("収める").tag(FitMode.fit)
                            Text("埋める").tag(FitMode.fill)
                        }
                        .pickerStyle(.segmented)
                        if model.fit == .fill {
                            HStack {
                                Text("拡大")
                                Slider(value: Binding(get: { model.crop.zoom },
                                                      set: { var c = model.crop; c.zoom = $0; model.setCrop(c) }),
                                       in: 1...ScreenCrop.maxZoom)
                                Text(String(format: "%.1f×", model.crop.zoom)).monospacedDigit().frame(width: 40, alignment: .trailing)
                            }
                            HStack {
                                Text("プレビューをドラッグして位置を調整").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("リセット") { model.resetCrop() }.disabled(model.crop == .identity)
                            }
                        }
                    }
                }
                presetSection
                Button("PNGを書き出す…") { model.exportPNG() }
                    .keyboardShortcut("e")
                    .buttonStyle(.borderedProminent)
                    .disabled(model.preview == nil)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }

    private var bezelSection: some View {
        GroupBox("ベゼル") {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(model.bezels) { bezel in
                        VStack(spacing: 2) {
                            Group {
                                if let thumb = model.thumbnails[bezel.bezelFile] {
                                    Image(decorative: thumb, scale: 1).resizable().scaledToFit()
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(height: 72)
                            Text(bezel.name).font(.caption2).lineLimit(1)
                        }
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(bezel.bezelFile == model.selectedBezelFile ? Color.accentColor.opacity(0.25) : Color.clear))
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedBezelFile = bezel.bezelFile }
                        .contextMenu {
                            Button("画面領域を編集…") { model.editingBezel = bezel }
                            Button("削除…", role: .destructive) { bezelToDelete = bezel }
                        }
                    }
                }
                HStack {
                    Button("ベゼルを追加…") { model.chooseBezelToAdd() }
                    Button("画面領域を編集…") { model.editingBezel = model.selectedBezel }
                        .disabled(model.selectedBezel == nil)
                }
                Text("ベゼル PNG はこの枠にドロップしても追加できます")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isBezelTargeted ? 2 : 0)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: isBezelTargeted ? 2 : 0))
            .onDrop(of: [.fileURL], isTargeted: $isBezelTargeted) { model.handle(providers: $0, target: .bezel) }
        }
    }

    /// 向き（回転）と切り抜き。スクショ読込後は常時表示する。
    @ViewBuilder
    private var orientationSection: some View {
        if model.screenshot != nil {
            GroupBox("向き・切り抜き") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button { model.rotateCounterClockwise() } label: {
                            Label("反時計回り", systemImage: "rotate.left")
                        }
                        Button { model.rotateClockwise() } label: {
                            Label("時計回り", systemImage: "rotate.right")
                        }
                        Spacer()
                        if !model.rotation.isIdentity {
                            Text("\(model.rotation.quarterTurns * 90)° 回転中").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("切り抜きで合わせる") { model.fit = .fill }
                        .disabled(model.fit == .fill)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 縦横比が合わないときの提案（回転すれば合うものを含む）。切り抜きは orientationSection で常時選べる。
    @ViewBuilder
    private var aspectSection: some View {
        if model.aspectMatches == false, let bezel = model.selectedBezel, let ratio = model.screenshotAspect {
            let suggestions = model.suggestedBezels
            GroupBox("縦横比が合いません") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "スクショ %.3f / %@の画面領域 %.3f", ratio, bezel.name,
                                bezel.aperture.width / bezel.aperture.height))
                        .font(.caption).foregroundStyle(.secondary)
                    if suggestions.isEmpty {
                        Text("合うベゼルがありません。切り抜きで合わせられます。").font(.caption)
                    } else {
                        Text(suggestions.count == 1
                             ? "このスクショには \(suggestions[0].bezel.name) が合います"
                             : "このスクショには次のベゼルが合います").font(.caption)
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                            Button {
                                model.apply(s)
                            } label: {
                                HStack {
                                    if let thumb = model.thumbnails[s.bezel.bezelFile] {
                                        Image(decorative: thumb, scale: 1).resizable().scaledToFit().frame(height: 32)
                                    }
                                    Text(s.needsRotation ? "回転して \(s.bezel.name) に切り替え" : "\(s.bezel.name) に切り替え")
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var backgroundSection: some View {
        GroupBox("背景") {
            VStack(alignment: .leading) {
                Picker("種類", selection: $model.backgroundKind) {
                    ForEach(BackgroundKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch model.backgroundKind {
                case .solid:
                    ColorPicker("色", selection: $model.solidColor)
                case .gradient:
                    ColorPicker("開始色", selection: $model.gradientStart)
                    ColorPicker("終了色", selection: $model.gradientEnd)
                    HStack {
                        Text("角度")
                        Slider(value: $model.gradientAngle, in: 0...360)
                        Text("\(Int(model.gradientAngle))°").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                case .transparent:
                    Text("背景なしで書き出します").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var presetSection: some View {
        GroupBox("プリセット") {
            HStack {
                Menu("呼び出し") {
                    if model.presets.isEmpty { Text("（なし）") }
                    ForEach(model.presets) { preset in
                        Button(preset.name) { model.apply(preset) }
                    }
                    if !model.presets.isEmpty {
                        Divider()
                        Menu("削除") {
                            ForEach(model.presets) { preset in
                                Button(preset.name, role: .destructive) { model.deletePreset(preset) }
                            }
                        }
                    }
                }
                Button("現在の設定を保存…") {
                    presetName = ""
                    showSavePreset = true
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
