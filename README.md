# FrameBezelApp

スクリーンショットに Apple 公式ベゼル（PNG）を合成して書き出す、自分専用の macOS アプリ。
仕様：`~/workspace/screenshot-frame-mac/spec.md`

> このソースは Linux 上で書かれており、**まだ一度もビルドしていません**。初回ビルドでコンパイルエラーが出る可能性があります。

## Xcode プロジェクトへの取り込み手順

1. Xcode → File → New → Project → **macOS > App**。Interface: SwiftUI、Language: Swift、Product Name: `FrameBezelApp`。Deployment Target は **macOS 14.0**。
2. 自動生成された `FrameBezelAppApp.swift` と `ContentView.swift` を削除（Move to Trash）。
3. このフォルダの `Sources/FrameCore/` と `Sources/App/` を Xcode のプロジェクトナビゲータへドラッグ。
   「Copy items if needed」はオフ（参照のまま）、「Create groups」、Target `FrameBezelApp` にチェック。
   - FrameCore と App は**同一ターゲット**に入れる想定（`import FrameCore` は不要）。
4. Target → Signing & Capabilities:
   - **App Sandbox を削除**（「−」ボタン）。個人用ツールとしてファイルアクセスを素直にするため。
   - Signing は Automatically manage signing（Apple Development）で可。
5. （任意）初期ベゼルを同梱する場合：`Bezels` という名前のフォルダに PNG を入れ、Xcode へ **Create folder references**（青いフォルダ）で追加。初回起動時だけ Application Support 側へコピーされる。
6. ⌘R で起動確認。

## ベゼルの用意

Apple Design Resources の Product Bezels dmg をマウントして PNG を取り出し、アプリの「ベゼルを追加…」またはベゼル欄へのドロップで追加します。追加時に画面領域が自動検出され、確認シートで枠の位置を見て数値を微調整できます。

## データの置き場所

`~/Library/Application Support/FrameApp/`
- `Bezels/` … ベゼル PNG と定義 JSON（`X.png` + `X.json`）
- `presets.json` … プリセット

.app を上書きしても消えません。

## /Applications への配置

```sh
xcodebuild -project FrameBezelApp.xcodeproj -scheme FrameBezelApp -configuration Release \
  -derivedDataPath build build
rm -rf /Applications/FrameBezelApp.app
cp -R build/Build/Products/Release/FrameBezelApp.app /Applications/
```

## 使い方

- 入力：プレビューへドラッグ＆ドロップ / 「ファイルを選択…」 / ⌘V またはペーストボタン
- 出力サイズはベゼル PNG と同じ（外側の余白は付けない）。背景はベゼルの透明部分にだけ現れる
- 書き出しはフル解像度で再合成。ファイル名は `{元名}_{機種名}.png` を提案、保存先フォルダは記憶

## 構成

- `Sources/FrameCore/` … UI 非依存の中核（Bezel / BezelDetector / Composer / BezelLibrary / Preset / ImageFile）
- `Sources/App/` … SwiftUI（FrameBezelApp / ContentView / AppModel / BezelEditorView）
