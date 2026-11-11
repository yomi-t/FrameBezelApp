import SwiftUI
import Foundation
import CoreGraphics
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false
    @State private var isBezelTargeted = false
    @State private var bezelToDelete: Bezel?
    @State private var showSavePreset = false
    @State private var presetName = ""
    @State private var dragStartCrop: ScreenCrop?

    /// @Observable のプロパティへ Binding を作る（`$model.x` の代わり）
    private var bindable: Bindable<AppModel> { Bindable(model) }

    private let swatches: [Color] = [.white, Color(white: 0.1), .blue, .orange, .green, .pink]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                previewPane
                Divider()
                inspector.frame(width: 300)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 820, minHeight: 560)
        .toolbar { toolbarContent }
        .sheet(item: bindable.editingBezel) { bezel in
            BezelEditorView(bezel: bezel).environment(model)
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

    // MARK: ツールバー

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.chooseScreenshot() } label: { Label("開く", systemImage: "folder") }
                .help("スクリーンショットを選択")
            Button { model.pasteFromClipboard() } label: { Label("ペースト", systemImage: "doc.on.clipboard") }
                .help("クリップボードから貼り付け (⌘V)")
        }
        ToolbarItemGroup {
            Button { model.rotateCounterClockwise() } label: { Label("左回転", systemImage: "rotate.left") }
                .disabled(model.screenshot == nil)
            Button { model.rotateClockwise() } label: { Label("右回転", systemImage: "rotate.right") }
                .disabled(model.screenshot == nil)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.exportPNG() } label: { Label("書き出し", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("e")
                .buttonStyle(.borderedProminent)
                .disabled(model.preview == nil)
                .help("PNG を書き出し (⌘E)")
        }
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
                        .background {
                            if model.backgroundKind == .transparent { Checkerboard() }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .gesture(cropDragGesture(in: geo.size, preview: preview))
                }
                .padding(24)
            } else {
                emptyState
            }
        }
        .overlay(alignment: .top) { aspectBanner }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3).padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { model.handle(providers: $0, target: .screenshot) }
        .onPasteCommand(of: [.fileURL, .image]) { _ = model.handle(providers: $0, target: .screenshot) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: model.screenshot == nil ? "square.and.arrow.down" : "iphone")
                .font(.system(size: 40, weight: .light))
            Text(model.screenshot == nil ? "スクリーンショットをドロップ" : "ベゼルを選択してください")
                .font(.title3)
            if model.screenshot == nil {
                Text("⌘V でペースト、または上の「開く」から選択").font(.callout)
            }
        }
        .foregroundStyle(.secondary)
        .padding(40)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(.tertiary))
        .padding(32)
    }

    /// 縦横比が合わないときの案内。設定パネルではなくプレビュー上に出す。
    @ViewBuilder
    private var aspectBanner: some View {
        if model.aspectMatches == false, let bezel = model.selectedBezel, let ratio = model.screenshotAspect {
            let suggestion = model.suggestedBezels.first
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(String(format: "縦横比が合いません（スクショ %.2f / %@ %.2f）", ratio, bezel.name,
                            bezel.aperture.width / bezel.aperture.height))
                    .font(.callout)
                Spacer(minLength: 8)
                if let s = suggestion {
                    Button(s.needsRotation ? "回転して \(s.bezel.name) に切り替え" : "\(s.bezel.name) に切り替え") {
                        model.apply(s)
                    }
                }
                if model.fit != .fill {
                    Button("切り抜きで合わせる") { model.fit = .fill }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.4)))
            .padding(12)
        }
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

    // MARK: 右：インスペクタ

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                bezelSection
                backgroundSection
                fitSection
                presetSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
    }

    private var bezelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("ベゼル")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(model.bezels) { bezel in
                    bezelTile(bezel)
                }
                Button { model.chooseBezelToAdd() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus").font(.title3)
                        Text("追加").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.tertiary))
                }
                .buttonStyle(.plain)
                .help("ベゼル PNG を追加（ここへドロップでも可）")
            }
            .padding(isBezelTargeted ? 4 : 0)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: isBezelTargeted ? 2 : 0))
            .onDrop(of: [.fileURL], isTargeted: $isBezelTargeted) { model.handle(providers: $0, target: .bezel) }

            Button("画面領域を編集…") { model.editingBezel = model.selectedBezel }
                .controlSize(.small)
                .disabled(model.selectedBezel == nil)
        }
    }

    private func bezelTile(_ bezel: Bezel) -> some View {
        let selected = bezel.bezelFile == model.selectedBezelFile
        return VStack(spacing: 4) {
            Group {
                if let thumb = model.thumbnails[bezel.bezelFile] {
                    Image(decorative: thumb, scale: 1).resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(height: 60)
            Text(bezel.name).font(.caption2).lineLimit(1)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedBezelFile = bezel.bezelFile }
        .contextMenu {
            Button("画面領域を編集…") { model.editingBezel = bezel }
            Button("削除…", role: .destructive) { bezelToDelete = bezel }
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("背景")
            Picker("種類", selection: bindable.backgroundKind) {
                ForEach([BackgroundKind.transparent, .solid, .gradient]) { Text($0.shortName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch model.backgroundKind {
            case .solid:
                HStack(spacing: 8) {
                    ForEach(swatches.indices, id: \.self) { i in
                        Button { model.solidColor = swatches[i] } label: {
                            Circle().fill(swatches[i]).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    ColorPicker("色", selection: bindable.solidColor).labelsHidden()
                }
            case .gradient:
                HStack {
                    ColorPicker("開始", selection: bindable.gradientStart)
                    ColorPicker("終了", selection: bindable.gradientEnd)
                }
                HStack {
                    Text("角度").font(.callout)
                    Slider(value: bindable.gradientAngle, in: 0...360)
                    Text("\(Int(model.gradientAngle))°").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            case .transparent:
                Text("ベゼルの外側は透明で書き出します").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var fitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("フィット")
            Picker("フィット", selection: bindable.fit) {
                Text("収める").tag(FitMode.fit)
                Text("埋める").tag(FitMode.fill)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if model.fit == .fill {
                HStack {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { model.crop.zoom },
                                          set: { var c = model.crop; c.zoom = $0; model.setCrop(c) }),
                           in: 1...ScreenCrop.maxZoom)
                    Text(String(format: "%.1f×", model.crop.zoom)).monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("プレビューをドラッグして位置を調整").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("リセット") { model.resetCrop() }
                        .controlSize(.small)
                        .disabled(model.crop == .identity)
                }
            }
        }
    }

    private var presetSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
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
            .padding(.top, 6)
        } label: {
            sectionHeader("プリセット")
        }
    }

    // MARK: 下部ステータスバー

    private var statusBar: some View {
        HStack(spacing: 12) {
            if let bezel = model.selectedBezel {
                let size = Composer.outputSize(bezel: bezel)
                Text(bezel.name)
                Text("\(size.width)×\(size.height)").monospacedDigit()
                Text("背景: \(model.backgroundKind.rawValue)")
            } else {
                Text("ベゼルが未選択です")
            }
            Spacer()
            if model.preview != nil { Text("⌘E で書き出し") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }
}

/// 透明部分を示す市松模様。
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            let light = Color(white: 0.95), dark = Color(white: 0.82)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : cell
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(dark))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
        }
    }
}
