# タスク票 006

## タスク：初回ビルドのコンパイルエラーを潰す（監査と修正）

- プロジェクト：フレーム合成アプリ（FrameBezelApp）
- 起票日：2026-11-11
- プロジェクト規約：このプロジェクトの CLAUDE.md（コード構成は 2026-11-11 の新構成が正）
- 前提：チケット 001〜005 の実装が、オーナーの Mac で Xcode プロジェクト化された

### 背景
オーナーが Xcode プロジェクトを作成してソースを取り込み、GitHub（yomi-t/FrameBezelApp、コミット ec61878）へ push した。ローカルで開いたところ**コンパイルエラーが出ている**。エラーの文面は未入手のため、プロジェクトのビルド設定を前提に全ファイルを監査して直す。

### 対象プロジェクトのビルド設定（FrameBezelApp.xcodeproj/project.xcproj から読み取り済み）
- Xcode 27 世代。MACOSX_DEPLOYMENT_TARGET はプロジェクト全体で **27.2**
- SWIFT_VERSION = 5.0（言語モードは Swift 5）
- ただし upcoming features が有効：
  - **SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor**（デフォルト分離が MainActor）
  - **SWIFT_APPROACHABLE_CONCURRENCY = YES**
  - **SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES**（import していないモジュールの extension メンバは見えない）
- ENABLE_APP_SANDBOX = NO（設定済み）
- FrameCore フォルダと FrameBezelApp フォルダは同一ターゲット（アプリ）のメンバー

### やること
1. 全 Swift ファイル（FrameCore/ 8本、FrameBezelApp/ 4本、テスト 2本）を精読し、コンパイルエラーの原因になり得る箇所を洗い出す。特に：
   - デフォルト MainActor 分離と衝突する箇所：FrameCore の値型（Bezel / Aperture / Preset / ComposeSettings / RGBAColor / BackgroundStyle / FitMode / ScreenCrop / Rotation 等）の Codable / Equatable / Identifiable / Sendable 適合、static プロパティ・static 関数の分離、プロトコル要件の nonisolated 要求との不整合
   - MemberImportVisibility：各ファイルが、使う extension メンバの定義モジュールを import しているか（例：CoreGraphics / AppKit / UniformTypeIdentifiers / ImageIO の不足）
   - その他、型不一致・API の使い方の誤り・参照漏れなどの通常のエラー
2. 保守的に直す：
   - 純粋なロジックである FrameCore 側は、必要な箇所に `nonisolated` を付けて分離デフォルトに依存しない形にするのが本命。ただし付け方で新たなエラー（Sendable 違反等）を生まないよう整合を取る
   - import の不足は明示 import の追加で直す
   - **振る舞いと公開 API の形は変えない**。どうしても変える必要がある場合は結果欄に理由を書く
3. README.md の構成説明（古い Sources/ パス）が残っていれば、新構成に合わせて直す

### 完了条件
- 監査結果（見つけた問題の一覧：ファイル・行・何がどう悪いか）が結果欄に書かれている
- 修正が入っている
- ビルド成功は主張しない（この環境ではビルド不可）。「残る可能性があるもの」も正直に結果欄へ

### 制約・禁止事項
- CLAUDE.md の禁止事項に従う
- project.xcproj（プロジェクトファイル）には触らない
- テストファイルは、エラー原因でない限り触らない

### 成果物の置き場
- コード：このプロジェクトの FrameCore/ と FrameBezelApp/
- 作業ログ：このファイルの「結果」欄

---

## 結果（実装役が記入）

- 状態：完了（修正済み・**ビルド未確認**。この環境では Xcode がなくビルド不可）
- やったこと：
  - 全 Swift ファイル（FrameCore 8 / App 4 / テスト 2 のうち UITests は未読）を精読して監査
  - 監査結果（原因になり得る箇所）：
    1. **デフォルト MainActor 分離 × FrameCore の全型**（Bezel.swift:4,21 / Composer.swift:4,20,27,34,45,74,82 / Preset.swift:4,20 / ImageRotation.swift:5,23 / AspectMatcher.swift:4,46 / BezelDetector.swift:4,17 / BezelLibrary.swift:4,17 / ImageFile.swift:5,18）。型が暗黙に @MainActor になり、Codable・Equatable・Identifiable の合成実装や `Error`/`LocalizedError`（`errorDescription` は nonisolated 要件）/`Sendable` 適合が MainActor 分離の適合になる。nonisolated な文脈（Codable の encode/decode、Error の伝播、static let 参照）との不整合でエラー・警告になる。
    2. **MemberImportVisibility**：AppModel.swift は CoreGraphics（CGImage）/ Foundation（`trimmingCharacters` 等）/ Combine（ObservableObject・@Published）、ContentView.swift・BezelEditorView.swift は CoreGraphics（CGImage, CGSize）/ Foundation（`String(format:)`）を import しておらず、SwiftUI 経由の推移的 import に依存していた。
    3. FrameCore 側の import は問題なし（Composer/BezelDetector/BezelLibrary/ImageRotation=CoreGraphics、ImageFile=ImageIO、他=Foundation）。
    4. その他の型不一致・API 誤用・参照漏れは、精読の範囲では見つからず。
  - 修正：1 は全型宣言に `nonisolated` を付与（`AspectMatcher.Suggestion` は入れ子なので個別に付与）。2 は明示 import を追加。3 は README の構成・手順を新構成（FrameCore/ と FrameBezelApp/）に更新。
- 生成・変更したファイル：FrameCore/*.swift 8本（宣言に `nonisolated` のみ追加）、FrameBezelApp/AppModel.swift・ContentView.swift・BezelEditorView.swift（import 追加のみ）、README.md、本チケット。project.xcproj・テストは未変更。
- 確認したこと：目視での整合確認のみ（nonisolated の付与漏れが無いことを grep で確認）。振る舞いと公開 API の形は変えていない。
- 要確認事項：
  - **ビルドは未実施。残る可能性**：実際のエラー文面が未入手のため、上記以外の原因（Xcode 27 固有の診断、UITests の中身〔未読〕、BezelLibrary を nonisolated class にしたことで出る Sendable 警告など）は否定できない。エラーが残る場合は文面をください。
  - `AppModel.init` 内の `selectedBezelFile = ...` は同一クラスの init 内なので `didSet` が走らず、起動直後は bezelImage が読まれない（最初のベゼルを選び直すまでプレビューが出ない）可能性がある。コンパイルエラーではなく振る舞いの話なので今回は未修正。直すか判断してください。
