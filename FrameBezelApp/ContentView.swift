import SwiftUI
import AppKit
import Foundation
import CoreGraphics
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false
    @State private var isBezelTargeted = false
    @State private var modelToDelete: BezelModelGroup?
    @State private var showSavePreset = false
    @State private var presetName = ""
    @State private var dragStartCrop: ScreenCrop?
    @State private var resizeStartCrop: ScreenCrop?
    @State private var wasSnapped = false
    /// 吸着が働く距離（画面上の pt）
    private static let snapDistance = 8.0
    private static let previewSpace = "previewArea"
    /// 収める・埋めるのボタンの背景の不透明度（1 で完全に不透明）
    private static let controlBackgroundOpacity = 0.96

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
        .confirmationDialog("「\(modelToDelete?.model ?? "")」を削除しますか？", isPresented: Binding(get: { modelToDelete != nil },
                                                                  set: { if !$0 { modelToDelete = nil } })) {
            Button("削除", role: .destructive) { if let g = modelToDelete { model.deleteModel(g) } }
        } message: {
            Text("この機種の向き・色違いのベゼル \(modelToDelete?.bezels.count ?? 0) 枚がすべて削除されます。")
        }
        .alert("ベゼルの取り込み結果", isPresented: Binding(get: { model.importSummary != nil },
                                                  set: { if !$0 { model.importSummary = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.importSummary ?? "") }
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
                    ZStack(alignment: .topLeading) {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .background {
                                if model.backgroundKind == .transparent && model.exportSize == nil { Checkerboard() }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .gesture(cropDragGesture(in: geo.size, preview: preview))
                            .pointerStyle(dragStartCrop == nil ? .grabIdle : .grabActive)
                        selectionBox(in: geo.size, preview: preview)
                    }
                    .coordinateSpace(.named(Self.previewSpace))
                }
                .padding(24)
            } else {
                emptyState
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 0) {
                aspectBanner
                fitControl
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
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
        if model.showsAspectBanner, let bezel = model.selectedBezel, let ratio = model.screenshotAspect {
            let suggestion = model.suggestedBezels.first
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(String(format: "縦横比が合いません（スクショ %.2f / %@ %.2f）", ratio, bezel.modelName,
                            bezel.aperture.width / bezel.aperture.height))
                    .font(.callout)
                Spacer(minLength: 8)
                if let s = suggestion {
                    Button(s.needsRotation ? "回転して \(s.bezel.modelName) に切り替え" : "\(s.bezel.modelName) に切り替え") {
                        model.apply(s)
                    }
                }
                Button("切り抜きで合わせる") { model.fillScreen() }
                Button { model.dismissAspectBanner() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("この警告を閉じる（新しい画像を読み込むと、また表示します）")
                .accessibilityLabel("警告を閉じる")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.4)))
            .padding(.top, 12)
            .padding(.horizontal, 12)
        }
    }

    // MARK: フィット切り替え（プレビュー上）と、ドラッグ/ピンチ/スクロールによる調整

    /// ボタンは押した時点で大きさを合わせるだけ（モードは持たない）。以後はドラッグで移動、角のハンドルで拡大縮小。
    @ViewBuilder
    private var fitControl: some View {
        if model.preview != nil {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button("収める") { model.fitToScreen() }
                        .buttonStyle(ResizeButtonStyle())
                    Button("埋める") { model.fillScreen() }
                        .buttonStyle(ResizeButtonStyle())
                }
            }
            .padding(12)
        }
    }
    
    struct ResizeButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(configuration.isPressed ? Color(.systemGray).opacity(0.5) : Color(.controlBackgroundColor).opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.15)))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// 吸着した瞬間にだけ、トラックパッドで「カチッ」と触覚フィードバックを返す。
    private func snapFeedback(_ snapped: Bool) {
        if snapped, !wasSnapped {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        wasSnapped = snapped
    }

    private enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        /// 矩形内の相対位置（0 = 左/上、1 = 右/下）
        var unit: CGPoint {
            switch self {
            case .topLeading: CGPoint(x: 0, y: 0)
            case .topTrailing: CGPoint(x: 1, y: 0)
            case .bottomLeading: CGPoint(x: 0, y: 1)
            case .bottomTrailing: CGPoint(x: 1, y: 1)
            }
        }
        var opposite: CGPoint { CGPoint(x: 1 - unit.x, y: 1 - unit.y) }
        /// ハンドルに乗せたときのリサイズ用カーソルの向き
        var pointerPosition: FrameResizePosition {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }
    }

    /// プレビュー上でのベゼル画像の表示位置と倍率（ベゼル 1px あたりの pt）。
    /// 書き出しサイズを選んでいるときは、キャンバス内でベゼルが拡大・中央寄せされている分を織り込む。
    private func displayedImage(in available: CGSize, preview: CGImage, bezel: Bezel) -> (origin: CGPoint, scale: Double) {
        let displayedW = min(available.width, available.height * Double(preview.width) / Double(preview.height))
        let displayedH = displayedW * Double(preview.height) / Double(preview.width)
        let origin = CGPoint(x: (available.width - displayedW) / 2, y: (available.height - displayedH) / 2)
        guard model.exportSize != nil, let canvas = model.exportCanvas else {
            return (origin, displayedW / Double(bezel.imageWidth))
        }
        let cw = Double(canvas.width), ch = Double(canvas.height)
        let fit = min(cw / Double(bezel.imageWidth), ch / Double(bezel.imageHeight))
        let perCanvasPx = displayedW / cw
        return (CGPoint(x: origin.x + (cw - Double(bezel.imageWidth) * fit) / 2 * perCanvasPx,
                        y: origin.y + (ch - Double(bezel.imageHeight) * fit) / 2 * perCanvasPx),
                fit * perCanvasPx)
    }

    /// スクショの外側に点線の枠と 4 隅のハンドルを出す。角をドラッグすると、対角を固定したまま拡大・縮小する。
    @ViewBuilder
    private func selectionBox(in available: CGSize, preview: CGImage) -> some View {
        if let bezel = model.selectedBezel, let screenshot = model.screenshot {
            let sw = Double(screenshot.width), sh = Double(screenshot.height)
            let (origin, k) = displayedImage(in: available, preview: preview, bezel: bezel)
            let rect = model.crop.imageRect(screenshotWidth: sw, screenshotHeight: sh, aperture: bezel.aperture)
            let box = CGRect(x: origin.x + rect.minX * k, y: origin.y + rect.minY * k,
                             width: rect.width * k, height: rect.height * k)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                    .allowsHitTesting(false)
                ForEach(Corner.allCases, id: \.self) { corner in
                    Rectangle()
                        .fill(Color.white)
                        .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                        .frame(width: 10, height: 10)
                        .padding(6) // 当たり判定を広げる
                        .contentShape(Rectangle())
                        .offset(x: box.minX + corner.unit.x * box.width - 11,
                                y: box.minY + corner.unit.y * box.height - 11)
                        .pointerStyle(.frameResize(position: corner.pointerPosition))
                        .gesture(resizeGesture(corner: corner, bezel: bezel, screenshotSize: CGSize(width: sw, height: sh), scale: k))
                }
            }
        }
    }

    private func resizeGesture(corner: Corner, bezel: Bezel, screenshotSize: CGSize, scale k: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.previewSpace))
            .onChanged { value in
                if resizeStartCrop == nil { resizeStartCrop = model.crop }
                guard let start = resizeStartCrop, k > 0 else { return }
                let sw = Double(screenshotSize.width), sh = Double(screenshotSize.height)
                let rect = start.imageRect(screenshotWidth: sw, screenshotHeight: sh, aperture: bezel.aperture)
                let point = { (u: CGPoint) in CGPoint(x: rect.minX + u.x * rect.width, y: rect.minY + u.y * rect.height) }
                let moved = point(corner.unit), anchor = point(corner.opposite)
                // 対角線方向への移動量から倍率を決める（縦横比は固定）
                let dx = moved.x - anchor.x, dy = moved.y - anchor.y
                let nx = dx + value.translation.width / k, ny = dy + value.translation.height / k
                let factor = (nx * dx + ny * dy) / (dx * dx + dy * dy)
                let snap = ScreenCrop.snapFactor(factor, moved: moved, anchor: anchor, aperture: bezel.aperture,
                                                 threshold: Self.snapDistance / k)
                model.setCrop(start.resized(by: snap.factor, anchor: anchor, screenshotWidth: sw, screenshotHeight: sh,
                                            aperture: bezel.aperture))
                snapFeedback(snap.snapped)
            }
            .onEnded { _ in resizeStartCrop = nil; wasSnapped = false }
    }

    /// プレビューのドラッグでスクショの表示位置を動かす。
    /// 画面上の移動量 → 合成座標（ベゼル等倍）→ 画面領域幅/高さで正規化。
    private func cropDragGesture(in available: CGSize, preview: CGImage) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard let bezel = model.selectedBezel else { return }
                if dragStartCrop == nil { dragStartCrop = model.crop }
                guard let start = dragStartCrop else { return }
                let pointsPerPixel = displayedImage(in: available, preview: preview, bezel: bezel).scale
                guard pointsPerPixel > 0 else { return }
                var c = start
                c.offsetX += value.translation.width / pointsPerPixel / bezel.aperture.width
                c.offsetY += value.translation.height / pointsPerPixel / bezel.aperture.height
                snapFeedback(model.moveCrop(to: c, snapThreshold: Self.snapDistance / pointsPerPixel))
            }
            .onEnded { _ in dragStartCrop = nil; wasSnapped = false }
    }

    // MARK: 右：インスペクタ

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                bezelSection
                transformSection
                backgroundSection
                exportSizeSection
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
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("機種")
            categoryPicker
            VStack(spacing: 6) {
                ForEach(model.visibleGroups) { group in
                    modelRow(group)
                }
                Button { model.chooseBezelToAdd() } label: {
                    HStack(spacing: 6) {
                        if model.isImporting {
                            ProgressView().controlSize(.small)
                            Text("取り込み中…").font(.caption)
                        } else {
                            Image(systemName: "plus")
                            Text("追加").font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.tertiary))
                }
                .buttonStyle(.plain)
                .disabled(model.isImporting)
                .help("ベゼル PNG、または機種名のフォルダを追加（ここへドロップでも可）")
            }
            .padding(isBezelTargeted ? 4 : 0)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: isBezelTargeted ? 2 : 0))
            .onDrop(of: [.fileURL], isTargeted: $isBezelTargeted) { model.handle(providers: $0, target: .bezel) }

            variantOptions

            Button("画面領域を編集…") { model.editingBezel = model.selectedRegisteredBezel }
                .controlSize(.small)
                .disabled(model.selectedBezel == nil)
        }
    }

    /// 機種の種類（iPhone / iPad / Mac / Watch）。取り込んだ機種にある種類だけを、機種名から自動で分類して出す。
    @ViewBuilder
    private var categoryPicker: some View {
        if model.categories.count > 1 {
            Picker("種類", selection: Binding(get: { model.browsingCategory }, set: { model.showCategory($0) })) {
                ForEach(model.categories) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// 選んだ機種の画面の形態・向き・フレーム色。選べるものが 2 つ以上あるときだけ出す。
    /// 向きと色は、選んでいる形態の中にあるものだけを出す（Duo の外側・開く、は縦だけ、など）。
    @ViewBuilder
    private var variantOptions: some View {
        if let group = model.selectedGroup, let current = model.selectedBezel {
            let variants = group.variants
            let colors = group.selectableColors(for: current.effectiveOrientation, variant: current.variant)
            if variants.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("形態")
                    Picker("形態", selection: Binding(get: { current.variant ?? variants[0] },
                                                    set: { model.selectVariant($0) })) {
                        ForEach(variants, id: \.self) { Text(BezelNaming.variantLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            // 向きが固定のデバイス（Mac・Watch など）は、選択肢が 1 つなので出さない
            let orientations = group.selectableOrientations(variant: current.variant)
            if orientations.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("向き")
                    Picker("向き", selection: Binding(get: { current.effectiveOrientation },
                                                     set: { model.selectOrientation($0) })) {
                        ForEach(orientations, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if model.isBezelTurned {
                        Text("この向きのベゼルは未登録のため、登録されているベゼルを回転して使っています")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if colors.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    sectionHeader("フレームの色")
                    Picker("フレームの色", selection: Binding(get: { current.color ?? colors[0] },
                                                          set: { model.selectColor($0) })) {
                        ForEach(colors, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    /// 機種 1 件の行。名前は折り返して全文を出す。種類のタブの中では、先頭の種類名を省いた短い名前にする。
    private func modelRow(_ group: BezelModelGroup) -> some View {
        let selected = group.model == model.selectedBezel?.modelName
        let rep = group.representative
        return HStack(spacing: 10) {
            Group {
                if let thumb = model.thumbnails[rep.bezelFile] {
                    Image(decorative: thumb, scale: 1).resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: 34, height: 44)
            Text(group.category.shortName(of: group.model))
                .font(.callout)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { model.selectModel(group) }
        .help(group.model) // 省略していない正式名称
        .accessibilityLabel(group.model)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            Button("この機種を削除…", role: .destructive) { modelToDelete = group }
        }
    }

    /// 画像のサイズと位置の数値入力。ドラッグ操作と同じ値を px で直接指定できる。
    @ViewBuilder
    private var transformSection: some View {
        if let frame = model.imageFrame {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("サイズと位置")
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        numberField("幅", frame.width) { model.setImageWidth($0) }
                        numberField("高さ", frame.height) { model.setImageHeight($0) }
                    }
                    GridRow {
                        numberField("X", frame.minX) { model.setImageOrigin(x: $0) }
                        numberField("Y", frame.minY) { model.setImageOrigin(y: $0) }
                    }
                }
                Text("単位は px。X・Y は画面領域の左上が原点です（縦横比は固定）")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func numberField(_ title: String, _ value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
            TextField(title, value: Binding(get: { value }, set: set), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
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

    /// 書き出しサイズ。App Store Connect の提出サイズを選ぶと、ベゼルを縦横比を保って最大に拡大し、余白を背景で埋めて中央に置く。
    private var exportSizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("書き出しサイズ")
            Picker("書き出しサイズ", selection: bindable.exportSizeID) {
                Text("ベゼルの元サイズ").tag(String?.none)
                ForEach(AppStoreSize.Family.allCases, id: \.self) { family in
                    Section("App Store Connect · \(family.rawValue)") {
                        ForEach(AppStoreSize.all.filter { $0.family == family }) { size in
                            Text(size.title + (size.isRequired ? "（必須）" : "")).tag(Optional(size.id))
                        }
                    }
                }
            }
            .labelsHidden()
            if let size = model.exportSize, let bezel = model.selectedBezel, let canvas = model.exportCanvas {
                let scale = min(Double(canvas.width) / Double(bezel.imageWidth), Double(canvas.height) / Double(bezel.imageHeight))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(canvas.width)×\(canvas.height) px · ベゼルを \(Int((scale * 100).rounded()))% で中央に配置")
                    Text(model.backgroundKind == .transparent
                         ? "App Store Connect は透明を受け付けないため、余白と透明部分は白で書き出します"
                         : "余白と透明部分は背景で埋めます")
                    if size.family == .iPhone || size.family == .iPad {
                        Text("ベゼルの向きに合わせて縦横を決めます")
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
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
                Text(bezel.modelName)
                Text("\(bezel.effectiveOrientation.label)向き")
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
