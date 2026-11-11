import SwiftUI

/// ベゼル追加直後の検出結果確認と、画面領域・名前の手動微調整。
struct BezelEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Bezel
    // environmentObject は init 時点で使えないので、画像は onAppear で読む
    @State private var loaded: CGImage?

    init(bezel: Bezel) {
        _draft = State(initialValue: bezel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("画面領域の確認").font(.headline)
            Text("赤い枠が検出された画面領域です。ズレていれば数値を直してください。")
                .font(.caption).foregroundStyle(.secondary)
            overlayPreview
            TextField("名前", text: $draft.name)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    field("X", $draft.aperture.x)
                    field("Y", $draft.aperture.y)
                    field("角丸", $draft.aperture.cornerRadius)
                }
                GridRow {
                    field("幅", $draft.aperture.width)
                    field("高さ", $draft.aperture.height)
                    Text("画像 \(draft.imageWidth)×\(draft.imageHeight)px").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("閉じる（変更を破棄）") { dismiss() }
                Button("保存") {
                    model.updateBezel(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 640)
        .onAppear { loaded = model.bezelImage(for: draft) }
    }

    private var overlayPreview: some View {
        GeometryReader { geo in
            let iw = CGFloat(max(draft.imageWidth, 1))
            let ih = CGFloat(max(draft.imageHeight, 1))
            let s = min(geo.size.width / iw, geo.size.height / ih)
            let a = draft.aperture
            ZStack(alignment: .topLeading) {
                if let loaded {
                    Image(decorative: loaded, scale: 1).resizable().frame(width: iw * s, height: ih * s)
                }
                RoundedRectangle(cornerRadius: CGFloat(a.cornerRadius) * s)
                    .stroke(Color.red, lineWidth: 2)
                    .frame(width: CGFloat(a.width) * s, height: CGFloat(a.height) * s)
                    .offset(x: CGFloat(a.x) * s, y: CGFloat(a.y) * s)
            }
            .frame(width: iw * s, height: ih * s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.gray.opacity(0.25))
        .frame(height: 380)
    }

    private func field(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 30, alignment: .leading)
            TextField(title, value: value, format: .number).frame(width: 70)
        }
    }
}
