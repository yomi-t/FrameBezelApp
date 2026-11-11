# FrameBezelApp

スクリーンショットに Apple 公式ベゼル（PNG）を合成して書き出す、自分専用の macOS アプリ。
仕様：`~/workspace/screenshot-frame-mac/spec.md`

> ソースは Linux 上で書かれ、Xcode プロジェクト化は Mac で行われました。この環境ではビルドできないため、ビルド成否はオーナーの Mac での確認が正です。

## Xcode プロジェクト

`FrameBezelApp.xcodeproj` を開いて ⌘R。`FrameCore/` と `FrameBezelApp/` は同一ターゲット（アプリ）のメンバーなので `import FrameCore` は不要です。

- App Sandbox は無効（個人用ツールとしてファイルアクセスを素直にするため）
- ビルド設定：デフォルト分離は MainActor、MemberImportVisibility 有効。そのため `FrameCore/` の型は `nonisolated` を明示し、各ファイルは使う API のモジュール（Foundation / CoreGraphics 等）を明示的に import している
- （任意）初期ベゼルを同梱する場合：`Bezels` という名前のフォルダに PNG を入れ、Xcode へ **Create folder references**（青いフォルダ）で追加。初回起動時だけ Application Support 側へコピーされる

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

## コマンドラインからの書き出し（AI・スクリプト向け）

起動引数に `--export` を付けると、画面を開かずに書き出して終了します。登録済みのベゼル（`~/Library/Application Support/FrameApp/`）を使います。

```sh
APP=build/Build/Products/Debug/FrameBezelApp.app/Contents/MacOS/FrameBezelApp
$APP --list-models                       # 機種・向き・色の一覧
$APP --list-sizes                        # App Store の提出サイズ一覧
$APP --export shot.png --model "iPhone 18 Pro" --color Silver \
     --size 1179x2556 --background "#101820" --output out.png
```

終了コードは 0 = 成功、1 = 失敗、2 = 引数の誤り。成功時は出力パスを標準出力に 1 行で出し、警告は標準エラーに出します。詳しくは `--help`。

## 構成

- `FrameCore/` … UI 非依存の中核（Bezel / BezelDetector / Composer / BezelLibrary / Preset / AspectMatcher / ImageRotation / ImageFile）
- `FrameBezelApp/` … SwiftUI（FrameBezelApp / ContentView / AppModel / BezelEditorView / Assets.xcassets）
- `FrameBezelAppTests/` … ユニットテスト（Swift Testing。`/test` で実行）
- `FrameBezelAppUITests/` … テンプレート由来の UI テストターゲット
