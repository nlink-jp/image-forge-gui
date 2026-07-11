# image-forge-gui

**探索的なローカル画像生成**のための macOS ネイティブアプリ。
[`image-forge`](https://github.com/nlink-jp/image-forge) CLI の常駐エンジン
（`serve`）を駆動する薄い SwiftUI フロントエンドです。モデルを選び、プロンプトを
書き、単発／バッチで生成し、結果をライブ進捗つきのギャラリーで見比べます。

macOS 14+（Apple silicon）。

## できること

- **Composer**（左）: プロンプト／ネガティブ（サイズ変更可能なエディタ）、モデル選択
  （各モデルのアーキテクチャとカタログ上のコンテンツ評価を表示、**Safe only** トグルで
  questionable／explicit を隠す）、**LoRA** セクション（インストール済み LoRA を複数
  重ねがけ、各 LoRA に重みスライダ。ベースモデルと**アーキテクチャが一致するものだけ**
  を提示。**トリガーワードを表示し、プロンプトへ自動挿入**）、**Init image**
  セクション＝**img2img**（画像をドロップ
  または選択＋**strength** スライダ）、基本パラメータ（seed とランダムトグル、steps、
  CFG、幅／高さ、hires）、**Advanced** セクション（sampler／scheduler／clip-skip の
  上書き）、バッチ**枚数**。**License** セクションはベースモデルと使用中 LoRA の
  ライセンスを常時表示し、特記制約（非商用・派生不可 等）のあるものを強調します。
  「Generate」で生成 — 生成中は **Cancel**（⌘.）に変わり、バッチを即座に中止できます。
- **Gallery**（メイン）: アクティブなライブラリの PNG のグリッド。クリックで選択
  （**⌘クリック**でトグル、**⇧クリック**で範囲選択）。下部には、単一選択時はインスペクタ
  （プロンプト・seed・サイズ）、複数選択時はバッチバー（**Delete**＝ゴミ箱／**Export**／
  **Move to Library**）を表示。ダブルクリック（または **View**）で **ライトボックス**
  （←/→ で前後移動、Finder 表示）。コンテキストメニュー・インスペクタ・ライトボックス
  から **Reuse Prompt**、**Reuse All Parameters**（"make similar"＝全設定をコピーするので、
  新しい seed でバリエーションになる）、**Use as Init Image**（Composer に送って img2img）、
  **Upscale…**（ESRGAN ×4 で現在のライブラリに出力）、**Copy Prompt** ／
  **Copy Negative Prompt**、**Reveal in Finder** が使えます。ヘッダー行の**ライブラリ切替**
  （フォルダメニュー）で名前付きライブラリを切り替え、新規追加（任意のフォルダ）、
  Finder 表示、一覧からの削除ができます。
- **ステータスバー**: エンジンの `ready` / `load` / `progress` / `done` / `error`
  イベントで駆動されるライブ進捗バーとメッセージ。エラーはインライン表示。

## ライブラリ

新しい生成は**アクティブなライブラリ**フォルダに書き込まれます。初回起動時の
**Default** ライブラリは `~/Library/Application Support/image-forge-gui/library/`
です（既存の画像がそのまま使えます）。ライブラリを切り替えると、新規生成の保存先が
変わると同時に、そのフォルダの既存 PNG がギャラリーに読み込まれます。image-forge が
各画像にパラメータ（A1111 互換＋`image-forge` JSON メタデータ）を埋め込むため、
プロンプト／seed／サイズは画像自体から復元されます。ライブラリ一覧とアクティブ選択は
`~/Library/Application Support/image-forge-gui/libraries.json` に永続化されます。

## しくみ

アプリは **`image-forge serve`** を一度だけ spawn して常駐させます（モデルロードと
Metal 初期化を毎回ではなく一度だけ支払う）。1 生成＝ stdin に 1 行の JSON 要求、
エンジンは stdout に JSON イベントを流し返し、アプリはそれを 1 行ずつデコードして
進捗更新と完成画像の追加を行います。モデル一覧は単発の
`image-forge models list --json` から取得します。

`claude-usage-lens-gui` / `quick-translate` と同じ構図です（Go CLI が実処理を持ち、
Swift は薄いフロントエンド）。

## 必要要件

`image-forge` CLI（darwin/arm64、Metal）。次の順で解決します。

1. `Contents/Resources` の**同梱**コピー（Developer-ID 署名＋notarize 済み＝信頼の
   起点。`make build-app` が埋め込む）
2. `$IMAGE_FORGE_BIN`
3. `~/bin/image-forge`
4. `PATH` 上の `image-forge`

## ビルド

```sh
make run                 # ビルド＋実行（デバッグ）
make build               # リリースバイナリ → .build/release/
make build-app           # 署名済み .app → dist/（CLI を同梱）
make package             # build-app ＋ notarize ＋ staple ＋ zip（リリース）
make test
```

`make build-app` は `CLI_BIN`（既定 `../image-forge/dist/image-forge`）から CLI を
同梱します。上書き例: `make build-app CLI_BIN=/path/to/image-forge`。

## 状況

動作する txt2img **＋ img2img** アプリ。Composer（単発＋バッチ、中止、Advanced 上書き、
初期画像）→ Gallery（ライトボックス、プロンプト／全パラメータ再利用、use-as-init、
ESRGAN アップスケール、切替可能なライブラリ）をライブ進捗つきで提供。再利用は現在の
セッションでも、ライブラリフォルダから読み込んだ画像（埋め込みメタデータから復元）でも
動作します。

**CLI 側のまま:** inpaint / ControlNet / LoRA とモデル管理（本アプリは txt2img／img2img
用の `serve` エンジンと、単発の `upscale` を駆動します）。

## なぜ Swift（ネイティブ macOS）

RFP に基づく判断: Wails GUI はデバッグ困難で不採用。本アプリは `quick-translate` /
`claude-usage-lens-gui` と同系統のネイティブ SwiftUI で、image-forge の安定した
`serve` プロトコルと `--json` を介して連携します。image-forge 同様 darwin/arm64 専用。

## ライセンス

MIT — [LICENSE](LICENSE) を参照。
