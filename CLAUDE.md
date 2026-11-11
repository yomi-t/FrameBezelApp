# FrameBezelApp（フレーム合成アプリ）— 実装規約

自分専用の macOS アプリ。スクショに Apple 公式ベゼルを合成して書き出すツール。
仕様の正は `~/workspace/screenshot-frame-mac/spec.md`。この文書と矛盾したら仕様が優先。

## 環境の前提
- このマシン（Linux）には Xcode がない。**ビルドはできないので、ビルド成功を主張しない**。Swift として正しいコードを書き、実ビルドはオーナーの Mac で行われる
- 対象：macOS 14+、Swift / SwiftUI、画像処理は Core Graphics / ImageIO。外部ライブラリは使わない
- App Sandbox は無効前提（個人用）。ベゼルや設定は `~/Library/Application Support/FrameApp/` に置く設計（仕様 §4 に合わせる。2026-11-11 統括が統一）

## コード構成
- `Sources/FrameCore/`
  - `Bezel.swift`：ベゼル定義モデル（名前、ファイル名、画像サイズ、画面領域 aperture{x,y,width,height,cornerRadius}）と JSON 入出力
  - `BezelDetector.swift`：ベゼル PNG のアルファ走査で画面領域を自動検出（透明ピクセルの外接矩形＋角丸推定）
  - `Composer.swift`：合成の中核。入力（スクショ CGImage、ベゼル定義、背景設定、余白）→ 出力 CGImage の独立関数として実装
  - `BezelLibrary.swift`：Application Support 内のベゼル管理（一覧、追加＝コピー＋検出＋JSON保存、削除、名前変更、初回起動時のバンドル同梱分のコピー）
- `Sources/App/`
  - `FrameBezelApp.swift`：@main
  - `ContentView.swift`：単一ウィンドウ。左プレビュー（ドラッグ＆ドロップ受け口）、右設定パネル
  - 設定：ベゼル選択、背景（単色 / グラデーション / 透明）、余白、フィット、書き出しボタン
  - 入力はドラッグ＆ドロップ / ファイル選択 / ペーストに対応
  - 書き出しはフル解像度で再合成して PNG 保存。ファイル名は `{元名}_{機種名}.png` を提案
- `README.md`：オーナーが Xcode プロジェクトを作成してこのソースを取り込む手順

## 禁止事項
- 外部送信・公開・課金に関わる実装
- 資格情報の取得・埋め込み
- このプロジェクトフォルダ外への書き込み
- 仕様にない判断が必要になったら、実装で決めずチケットの結果欄に「要確認」として残す

## 流儀
- 中核ロジック（検出・合成）は UI から分離し、入出力が明確な形にする
- コメントは「なぜ」が非自明な箇所だけ
- 完了時はチケットの「結果」欄を埋める（やったこと / 変更ファイル / 確認したこと / 要確認事項）
