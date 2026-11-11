# FrameBezelApp（フレーム合成アプリ）— 実装規約

自分専用の macOS アプリ。スクショに Apple 公式ベゼルを合成して書き出すツール。
仕様の正は `~/workspace/screenshot-frame-mac/spec.md`。この文書と矛盾したら仕様が優先。

## 環境の前提
- Mac（Xcode あり）で作業する。`FrameBezelApp.xcodeproj` / scheme `FrameBezelApp`。ビルドは `/build`、テストは `/test`（`.claude/commands/`）。Swift 編集後は hook（`.claude/hooks/build-check.sh`）が自動ビルドし、エラーを返す。**ビルド/テストを実行していない場合は成功を主張しない**
- コードは **Swift 6 系**（Swift 6 言語モード）で書く。strict concurrency 前提：データ競合を起こさない設計にし、`Sendable` / actor 分離を明示する。プロジェクトは `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` なので、UI 非依存の `FrameCore/` の型は `nonisolated`（必要なら `Sendable`）を付ける
- 対象：macOS 14+、Swift / SwiftUI、画像処理は Core Graphics / ImageIO。外部ライブラリは使わない
- App Sandbox は無効前提（個人用）。ベゼルや設定は `~/Library/Application Support/FrameApp/` に置く設計（仕様 §4 に合わせる。2026-11-11 統括が統一）

## コード構成（2026-11-11 オーナーが Xcode プロジェクト化し、構成を変更。以後はこちらが正）
- `FrameCore/`（リポジトリ直下）
  - `Bezel.swift`：ベゼル定義モデル（名前、ファイル名、画像サイズ、画面領域 aperture{x,y,width,height,cornerRadius}）と JSON 入出力
  - `BezelDetector.swift`：ベゼル PNG のアルファ走査で画面領域を自動検出（透明ピクセルの外接矩形＋角丸推定）
  - `Composer.swift`：合成の中核。入力（スクショ CGImage、ベゼル定義、背景設定）→ 出力 CGImage の独立関数として実装
  - `BezelLibrary.swift`：Application Support 内のベゼル管理（一覧、追加＝コピー＋検出＋JSON保存、フォルダ丸ごと取り込み、削除、初回起動時のバンドル同梱分のコピー）
  - `BezelCatalog.swift`：Apple 配布ファイル名の解析と、機種ごとのグルーピング・向き/色の選択ロジック。`BezelLibrary.importFolder` がフォルダ丸ごと取り込む。機種名は**ファイル名を優先**して決め（`機種 - 色 - 向き`、`MacBook … 13-inch 色`、`Studio Display … On Dark Background`、Apple Watch の `42mm` に対応。Duo の `Night Sky - Inner Open Landscape` は、色 `Night Sky`・形態 `Inner Open`・向き `landscape` に分け、形態（`Bezel.variant`）は向き・色とは別の選択肢にする）、フォルダ名はファイル名に機種が無いときだけ使う。`PNG` / `Portrait` / `Bezel-…` のフォルダ名は機種名にしない。機種名・ベゼル名には配布物由来の `Bezel` 接頭辞を付けず、機種の名前だけにする（`BezelNaming.officialName`）
  - 向きの扱い：回転するのは iPhone・iPad のみ（`DeviceCategory.rotates`。Mac・Watch など向きが固定のデバイスは、向きの選択肢を出さず回転もしない）。その向きのベゼルが登録されていなければ、逆向きの登録ベゼルを 90° 回して使う（`Bezel.turned(to:)` と `BezelModelGroup.selection` / `bestSelection`）。縦→横は反時計回り（Apple の横向きはノッチが左）、横→縦は時計回り。保存データは回さず、合成・書き出しには回した定義と回した画像を渡す。向きが登録されていれば回転しない
  - `DeviceCategory.swift`：機種名から iPhone / iPad / Mac / Watch / その他 へ自動分類（保存データには持たない）。機種一覧の種類切り替えに使う
  - `HeadlessExport.swift`：コマンドライン書き出し（`--export` 等）。引数の解釈と実行は UI から分離。`FrameBezelApp.swift` の `Launcher` が起動引数を見て GUI / CLI を切り替える
  - その他：`Preset.swift`、`AspectMatcher.swift`、`ImageRotation.swift`、`ImageFile.swift`
- `FrameBezelApp/`（リポジトリ直下、アプリターゲットのソース）
  - `FrameBezelApp.swift`：@main
  - `ContentView.swift`：単一ウィンドウ。左プレビュー（ドラッグ＆ドロップ受け口）、右設定パネル
  - `AppModel.swift`、`BezelEditorView.swift`、`Assets.xcassets/`
  - 設定：ベゼル選択、背景（単色 / グラデーション / 透明、デフォルトは透明）、フィット、書き出しボタン
  - 入力はドラッグ＆ドロップ / ファイル選択 / ペーストに対応
  - 書き出しはフル解像度で再合成して PNG 保存。ファイル名は `{元名}_{機種名}.png` を提案
- `FrameBezelApp.xcodeproj/project.xcproj`：Xcode 27 世代の新形式プロジェクトファイル（JSON）。オーナーの Mac で生成されたものが正
- `FrameBezelAppTests/`：Swift Testing のユニットテスト（領域別のファイル。共通ヘルパーは `TestSupport.swift`）。`AppModel` は `init(library:defaults:)` に一時フォルダのライブラリと専用 UserDefaults を渡して試すので、本物の Application Support には触れない
- `FrameBezelAppUITests/`：テンプレート由来の UI テストターゲット
- `README.md`：手順と構成の説明（パスはこの構成に合わせて更新すること）

## 禁止事項
- 外部送信・公開・課金に関わる実装
- 資格情報の取得・埋め込み
- このプロジェクトフォルダ外への書き込み（唯一の例外：`/install` コマンドが `.claude/scripts/install.sh` 経由で `/Applications/FrameBezelApp.app` を置き換えること。それ以外の方法で /Applications に書き込まない）
- 仕様にない判断が必要になったら、実装で決めずチケットの結果欄に「要確認」として残す

## 流儀
- 中核ロジック（検出・合成）は UI から分離し、入出力が明確な形にする
- コメントは「なぜ」が非自明な箇所だけ
- 完了時はチケットの「結果」欄を埋める（やったこと / 変更ファイル / 確認したこと / 要確認事項）
