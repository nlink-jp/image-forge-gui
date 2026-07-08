# RFP: image-forge-gui

> Generated: 2026-07-07
> Status: Draft

## 1. 問題定義 (Problem Statement)

image-forge の CLI は強力だが、**多数のプロンプトを試し・良い結果を選んで保存し・過去の
設定を再利用する探索的ワークフロー**はターミナルでは煩雑になる。`image-forge-gui` は、
image-forge の常駐エンジン（`serve`）を駆動する **macOS ネイティブ（Swift/SwiftUI）
フロントエンド**で、**プロンプトのバッチ生成・ギャラリーでの選別保存・生成履歴からの
再利用**を提供する。対象ユーザーは image-forge を使うローカル画像生成ユーザー（主に
自分／nlink-jp）。

## 2. 機能仕様 (Functional Specification)

### 画面 / UI サーフェス
- **Composer**: プロンプト／ネガティブ、モデル選択（`models list --json`）、基本
  パラメータ（seed・steps・cfg・サイズ・sampler／scheduler、未指定はプロファイル既定）、
  バッチ設定（枚数 N・seed モード＝固定連番／ランダム）、hires ON/OFF、img2img（初期画像
  ドロップ＋strength）。「生成」でキュー投入。
- **Queue / 進捗**: バッチキュー、serve イベントによるライブ進捗、キャンセル。
- **Gallery**: 結果グリッド、選択／お気に入り、右クリックで保存・パラメータ再利用・削除・
  アップスケール（`image-forge upscale`）。
- **History**: 過去生成の一覧（プロンプト＋パラメータ＋サムネ）、クリックで Composer に
  復元、検索。
- **Inspector**: 選択画像の全パラメータ表示・プロンプトコピー・再利用。

### 入出力 (Input / Output)
- **バックエンド連携**: `image-forge serve` を常駐で spawn。1 生成＝ stdin に 1 行 JSON
  要求、stdout から `ready` / `load` / `progress` / `done` / `error` イベントを受信。
  モデル一覧は `image-forge models list --json`（単発）。
- **出力**: 生成 PNG はアプリ管理のライブラリフォルダに自動保存（各 PNG は image-forge が
  v0.12.0 のメタデータ＝A1111 互換 `parameters`＋`image-forge` JSON を埋め込む → 画像自体が
  自己記述的）。エクスポートは選択画像を任意フォルダへコピー＋「Finder で表示」。

### 設定 (Configuration)
- 同梱 image-forge バイナリ（.app 内 Resources を既定で使用）、ライブラリ（出力）フォルダ、
  既定モデル。アプリ設定は UserDefaults。

### 外部依存 (External Dependencies)
- **同梱 image-forge バイナリ**（darwin/arm64、署名済み）。ネットワークサービス依存なし。

## 3. 設計判断 (Design Decisions)

- **Swift/SwiftUI ネイティブ macOS**。Wails はデバッグ困難という利用者判断で不採用。
  `claude-usage-lens-gui` / `quick-translate` と同系統（Swift の薄いフロントエンドが CLI を
  駆動）。
- **`image-forge serve` を子プロセス駆動**。image-forge の engine は `internal/` パッケージで
  別モジュールから import 不可のため、子プロセス駆動が唯一かつ最良の道。`serve` は GUI
  フロントエンドのために設計された常駐モード。
- **署名済み image-forge バイナリを .app に同梱**（自己完結配布）。**履歴は SwiftData**
  （SwiftUI ネイティブ統合、macOS 14+）。
- **補完**: image-forge CLI のフロントエンド。
- **アプリアイコンは image-forge 自身で生成（ドッグフーディング）**。採用: realvisxl-v5 で
  「アンビル＋ハンマー＋虹色の火花＝画像を鍛造する」（`assets/app-icon-source.png`、seed 1001。
  プロンプト／seed は PNG メタデータに埋め込み済みで再現可能）。`.icns` 化は Phase 3。
- **スコープ外**: inpaint / ControlNet（Phase 2 以降）、モデル pull／量子化（CLI 側のまま、
  GUI は list＋生成に専念）、学習、Windows/Linux（image-forge 同様 darwin/arm64 専用）。

## 4. 開発計画 (Development Plan)

### Phase 1: Core
Swift アプリ scaffold ＋ **serve 駆動層**（spawn・JSON 送受・イベント解析・エラー処理）＋
モデル一覧 ＋ Composer ＋ txt2img 単発／バッチ ＋ Gallery ＋ ライブ進捗。ユニットテスト
（JSON エンコード／イベント解析／serve プロトコルはモック可能に設計）。

### Phase 2: Features
SwiftData 履歴 ＋ プロンプト再利用 ＋ お気に入り／エクスポート ＋ img2img（画像 D&D＋
strength）＋ hires トグル ＋ upscale（ギャラリー右クリック）。

### Phase 3: Release
磨き込み ＋ docs（README ja/en）＋ **アプリアイコン（生成アートから `.icns` 生成）** ＋
Developer ID 署名 ＋ notarize（.app、必要なら .dmg）＋ リリース。

各 Phase は独立レビュー可。

## 5. Required API Scopes / Permissions

**なし**（外部サービス依存なし、ローカル子プロセスのみ）。**非サンドボックスの Developer ID
直接配布**（子プロセス spawn ＋ ファイル書込のため。App Store 非対象。他の util-series Swift
アプリと同様）。

## 6. Series Placement

Series: **util-series**
Reason: image-forge 本体が util-series。その GUI も、`claude-usage-lens-gui` /
`csv-editor` / `mail-analyzer-gui` 等の util-series GUI と同様にここに属する。

## 7. External Platform Constraints

**なし**（外部プラットフォーム無し）。技術制約: **darwin/arm64 専用**（同梱 image-forge が
arm64/Metal）、**macOS 14+**（SwiftData 要件）。

---

## Discussion Log

- **問題定義／名前**: 名前は `image-forge-gui`（`*-gui` 命名規則に一致）。問題定義は
  「探索的ワークフローを GUI で」で確定。
- **技術スタック**: Wails は「まともに動かずデバッグ苦労」という利用者判断で不採用 →
  Swift/SwiftUI ネイティブに決定（既存 Swift アプリと同系統）。
- **アーキテクチャ**: engine は internal で import 不可 → `image-forge serve` 子プロセス
  駆動が唯一の道（serve は GUI 用に設計済み）。
- **バイナリ入手**: 選択肢（PATH/~/bin 参照 ＋設定 ／ .app 同梱）→ **.app 同梱**（自己完結
  配布）を選択。
- **履歴保存**: SwiftData ／ SQLite(GRDB) ／ JSON → **SwiftData**（SwiftUI ネイティブ統合）。
- **MVP スコープ**: txt2img+hires ／ +upscale ／ +img2img → **img2img も v1 に含める**
  （txt2img バッチ＋hires＋img2img＋upscale。inpaint/ControlNet は Phase 2）。
- **アプリアイコン**: image-forge 自身で 3 候補生成し、realvisxl-v5 の「アンビル＋虹色火花」
  （候補 A）を採用。ドッグフーディング。生成メタデータ（v0.12.0）で再現可能。
