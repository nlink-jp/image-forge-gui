# ADR-0001: モデル管理を GUI に取り込む

- Status: Accepted
- Date: 2026-07-11

## Context

RFP（docs/ja/image-forge-gui-rfp.ja.md §3）は意図的に **モデル管理を CLI に残した**:
「GUI は一覧と生成だけ」。アプリは生成のために `image-forge serve` を駆動し、Composer の
モデルピッカーを埋めるために `image-forge models list --json` を一度呼ぶ — それだけである。

しかしこれは **初回起動**に関して、境界を間違った場所に引いている。新規インストールには
モデルが 1 つも無く、アプリは利用者をターミナルへ行き止まらせる:

- `ComposerView` は空のピッカーを表示し、`diffusionModels.isEmpty` のとき Generate を
  無効化する。
- LoRA セクションは文字どおり `image-forge models pull lcm-lora-sdxl` を実行せよと
  利用者に指示する。
- `ServeClient.listModels()` は **インストール済み**モデルしかデコードしない。CLI が既に
  公開しているキュレーション済みカタログ（`models list --catalog --json`）はどこにも
  出てこない。

「技術的な知識は要らない」ことが全体の前提であるアプリにとって、最初の操作が CLI コマンドで
あることは最大の UX 上の欠落である（GUI issue #3）。

CLI は必要なものをすべて一発サブコマンドとして既に提供している — エンジンを変える必要は
無い:

- `models list --catalog --json` — キュレーション済みカタログ（arch・rating・license・
  RAM ティア・`needs_opt_in`・`installed`）。
- `models pull <name> [--allow-nsfw]` — ダウンロード + 登録。**進捗を stderr へ
  ストリーム**する（再開/リトライあり）。
- `models rm <name> [--purge]` — レジストリエントリを削除し、`--purge` を付けると数 GB の
  重みファイルを回収する（共有されているファイル / dir 外のファイルは保つ）。

## Decision

**RFP の境界を見直す: モデルの取得と削除を GUI に移す。**駆動には既存の CLI 一発
サブコマンドを使う。diffusion エンジン・カタログ・レジストリは image-forge が所有した
ままであり、GUI は CLI 利用者が実行するのと同じサブコマンドを*駆動する*だけである —
すでに `serve` と `upscale` を駆動しているのと全く同じように。

具体的には:

- 専用の **Manage Models** ウィンドウ（メニュー + Composer の行き止まりだった空状態を
  置き換える「Get your first model…」ボタン）。モーダルシートではなくウィンドウに
  するのは、Composer の隣に開いたままにできるようにするためである。
- `models list --catalog --json` でカタログを **Browse** し、arch・rating・license・
  RAM ティアと、インストール済みバッジを表示する。
- `models pull` で **Install** し、**進捗をライブ表示**する。これには*ストリーミングする*
  一発実行が必要である（既存の `runOneShot` は終了時に stdout を返すだけ）。そこで
  `runStreaming(args:onLine:)` を追加し、stderr の進捗行が届き次第表面化させる。2 本の
  パイプによるデッドロックを直したときの並行 drain の作法を再利用する。
- `models rm --purge` で **Remove** し、実際にディスクを回収する（GUI 利用者には数 GB の
  ファイルを解放する他の手段が無い）。
- **NSFW のオプトイン**を尊重する: `needs_opt_in` のカタログエントリは、`--allow-nsfw` を
  渡す前に明示的な確認を要求する。

当面は対象外（CLI に残す）: `quantize`・`import`・`models gc`・ディスク使用量の報告。
`gc` とディスク使用量は自然な次の増分である。

## Consequences

- GUI が初回起動において「技術的な知識は要らない」を実現する。
- CLI への新たな結合: GUI が依存するサブコマンドの形が 3 つ増える
  （`list --catalog --json`・`pull`・`rm --purge`）。これらは安定しており、名前ベースで、
  既に CLI 利用者がモデルを管理する方法そのものである。`pull` の stderr 進捗テキストは
  ベストエフォート（寛容にパースし、決して致命的にしない）。
- 信頼境界は変わらない: GUI は依然として同梱・署名済みの `image-forge` バイナリ
  （`BinaryResolver`）だけを実行する。それが描画に加えて管理にも使われるようになる。
- RFP の「GUI は一覧と生成だけ」という記述は、本 ADR によって置き換えられる。
