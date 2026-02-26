# CLAUDE.md — AIアシスタント向けガイド (mc-server)

## プロジェクト概要

このリポジトリは、**DockerベースのMinecraftサーバー管理システム**です。
複数のホストが Cloudflare R2 オブジェクトストレージ上の単一ワールドデータを共有できます。
主な機能: 悲観的ロック機構による同時起動防止、起動・停止時のワールドデータ自動同期、
Discord イベント通知、Minecraft ボスバーによるホスト表示。

**言語スタック:** Ruby 3.2 (主要)、Bash/Batch (オーケストレーション)、MCFunction (データパック)

---

## リポジトリ構成

```
mc-server/
├── .github/
│   └── pull_request_template.md   # PRテンプレート (日本語、レビュー接頭辞定義)
├── datapack/
│   └── host_bossbar/              # ボスバー表示用 Minecraft データパック
│       ├── pack.mcmeta
│       └── data/
│           ├── minecraft/tags/functions/load.json
│           └── hostbossbar/functions/
│               ├── load.mcfunction
│               └── tick.mcfunction
├── docker/
│   └── ruby/
│       └── Dockerfile             # aws-sdk-s3 gem 入りカスタム Ruby イメージ
├── scripts/
│   ├── lib/
│   │   └── rcon_client.rb         # 共有 RCON プロトコル実装
│   ├── bossbar.rb                 # ボスバーでホスト名をゲーム内表示
│   ├── discord_notify.rb          # サーバー・プレイヤーイベントを Discord に通知
│   ├── measure-performance.sh     # RCON 経由で TPS/MSPT/CPU/メモリを計測
│   └── sync.rb                    # Cloudflare R2 とのワールドデータ同期
├── test/
│   └── test_log_rotation.sh       # ログローテーション検出テスト
├── .env.example                   # 環境変数設定テンプレート
├── .gitignore
├── README.md                      # 日本語ドキュメント (アーキテクチャ図含む)
├── compose.yml                    # Docker Compose サービス定義
├── start-server.sh / start-server.bat   # クロスプラットフォーム起動スクリプト
└── stop-server.sh  / stop-server.bat    # クロスプラットフォーム停止スクリプト
```

---

## Docker サービス

`compose.yml` で定義。依存関係の順に起動されます。

| サービス | コンテナ名 | 目的 | ライフサイクル |
|---|---|---|---|
| `sync-init` | `mc_sync_init` | R2 ロック取得・ワールドデータダウンロード | `server` 起動前に一度だけ実行 |
| `server` | `mc_server` | Minecraft サーバー (Forge 1.20.1、4GB RAM) | `restart: unless-stopped` |
| `sync-shutdown` | `mc_sync_shutdown` | ワールドデータアップロード・ロック解放 | 停止時に一度だけ実行 (`shutdown` プロファイル) |
| `bossbar-manager` | `mc_bossbar` | RCON 経由でホスト名をゲーム内表示 | サーバー起動後に一度だけ実行 |
| `discord-notify` | `mc_discord_notify` | サーバーログ監視・Discord 通知 | サーバーと並行して実行 |

`sync-shutdown` は `shutdown` プロファイルで保護されており、停止スクリプトから明示的に起動されます。

---

## 環境変数の設定

`.env.example` を `.env` にコピーし、すべての値を入力してから起動してください。

| 変数名 | 説明 |
|---|---|
| `R2_ACCOUNT_ID` | Cloudflare アカウント ID |
| `R2_ACCESS_KEY_ID` | R2 API アクセスキー |
| `R2_SECRET_ACCESS_KEY` | R2 API シークレットキー |
| `R2_BUCKET_NAME` | ワールドデータ用バケット名 |
| `R2_ENDPOINT` | `https://<account_id>.r2.cloudflarestorage.com` |
| `LOCAL_DATA_DIR` | ワールドデータのローカルマウントパス (デフォルト: `./data`) |
| `HOST_DISPLAY_NAME` | ゲーム内に表示されるホスト名 (ホストごとに一意にすること) |
| `RCON_PASSWORD` | Minecraft RCON パスワード (デフォルト: `minecraft`) |
| `DISCORD_WEBHOOK_URL` | イベント通知用 Discord Webhook URL |

開発・テスト時は `.env.dev` を作成し (`.gitignore` 済み)、スクリプトに `dev` 引数を渡すと使用されます。

**重要:** `.env` や認証情報を含むファイルは絶対にコミットしないでください。
`.gitignore` は `.env.example` 以外の `.env.*` を除外しています。

---

## 開発ワークフロー

### サーバーの起動・停止

**Linux/Mac:**
```bash
./start-server.sh        # .env を使用
./start-server.sh dev    # .env.dev を使用
./stop-server.sh
./stop-server.sh dev
```

**Windows:**
```batch
start-server.bat
start-server.bat dev
stop-server.bat
```

起動スクリプトは初回実行時にカスタム Ruby Docker イメージを自動ビルドします。

### よく使う Docker コマンド

```bash
# サーバーログをリアルタイム確認
docker logs -f mc_server

# 手動起動・停止 (同期なし)
docker compose up -d
docker compose down

# R2 ロックの確認・解放 (サーバーがクラッシュしてロックが残った場合)
docker compose run --rm sync-init ruby /app/sync.rb check-lock
docker compose run --rm sync-init ruby /app/sync.rb unlock

# データの強制ダウンロード・アップロード
docker compose run --rm sync-init ruby /app/sync.rb download
docker compose run --rm sync-init ruby /app/sync.rb upload
```

### sync.rb サブコマンド

`scripts/sync.rb` は以下のサブコマンドを受け付けます。

| コマンド | 説明 |
|---|---|
| `init` | ロック取得 + データダウンロード (サーバー起動前に実行) |
| `shutdown` | データアップロード + ロック解放 (サーバー停止後に実行) |
| `download` | ダウンロードのみ |
| `upload` | アップロードのみ |
| `lock` | ロック取得のみ |
| `unlock` | ロック解放のみ |
| `check-lock` | 現在のロック状態を表示 |

---

## 主要スクリプトの設計

### `scripts/sync.rb` — ワールドデータ同期

- クラス: `R2Sync`
- Cloudflare R2 (S3 互換 API) との通信に `aws-sdk-s3` gem を使用
- **ロック機構:** ホスト名・タイムスタンプ・PID を含む `server.lock` JSON ファイルを R2 に保存。
  複数ホストの同時起動を防ぎます。
- **データ形式:** ワールドデータは `server-data.tar.gz` として圧縮。
  Docker 内でのファイル所有権を統一するため `--owner=1000 --group=1000` を使用。
- 起動時に必須環境変数を検証し、不足があればコード 1 で終了します。

### `scripts/discord_notify.rb` — Discord 通知

- クラス: `DiscordWebhook`、`LogWatcher`、`DiscordNotifier`
- inode 追跡によるリアルタイムのログファイル監視 (ログローテーション対応)
- 検出パターン: サーバー起動・停止、プレイヤー参加・退出
- 色分けされた Discord Embed を送信 (青=オンライン、緑=参加、橙=退出、赤=オフライン)
- グレースフルシャットダウンのための SIGTERM/SIGINT ハンドラーを登録

### `scripts/bossbar.rb` — ゲーム内ホスト表示

- クラス: `BossbarManager`
- サーバーロード完了後に RCON で接続
- 接続リトライ (`MAX_RETRIES`・`RETRY_INTERVAL` 環境変数で設定可能)
- `HOST_DISPLAY_NAME` を表示するボスバーを作成・表示するコマンドを実行

### `scripts/lib/rcon_client.rb` — 共有 RCON ライブラリ

- クラス: `RconClient`
- TCP 上の RCON プロトコルをカスタム実装
- カスタム例外: `AuthenticationError`、`ConnectionError`
- バイナリパケットフレーミングと UTF-8 エンコーディングを処理
- `bossbar.rb` と `discord_notify.rb` の両方で共有

---

## コーディング規約

- **frozen string literal:** すべての Ruby ファイルは `# frozen_string_literal: true` で始める。
- **クラスベースのアーキテクチャ:** 各スクリプトは役割が明確なクラスを 1 つ以上公開する。
- **コメントは日本語** — 意図的なものであり、維持すること。
- **コンソール出力に絵文字を使用** — 視覚的な状態把握のために使用しているため、このスタイルを維持すること。
- **エラーハンドリング:** ドメインエラーにはカスタム例外クラスを使用。R2 操作では `Aws::S3::Errors::ServiceError` を rescue する。
- **テストフレームワークなし:** テストは Docker 環境を直接操作する bash スクリプト (`test/test_log_rotation.sh`) 1 つのみ。
- **否定条件に `unless` を使用しない** — `unless bool` ではなく `if !bool` スタイルを使用すること (コミット `b324b63` 参照)。
- **所有権:** Docker ボリューム内のワールドデータファイルは必ず UID/GID 1000 で所有すること。

---

## プルリクエストの規約

PR は `.github/pull_request_template.md` のテンプレートに従います。

- **日本語**で記述
- セクション: 概要、背景・動機、新規追加ファイル、変更内容、技術的な判断、スクリーンショット、レビューに関して
- **レビューコメントの接頭辞:**
  - `[must]` — 必須の変更
  - `[imo]` — 意見 (修正必須ではない)
  - `[nits]` — 些細な指摘
  - `[ask]` — 質問
  - `[fyi]` — 参考情報

**レビュー重点項目:** 命名の一貫性、セキュリティ上の懸念、パフォーマンスへの影響、
メソッドの責務分離、変数名・コメントの誤字脱字。

---

## AI アシスタントへの重要な制約

**本番環境 (引数なし) の操作は絶対に行わないこと。**

このリポジトリには本番環境と開発環境の2つの環境があります。AI アシスタントは以下の規則を厳守してください。

### 禁止事項

- `./start-server.sh`、`./stop-server.sh`、`start-server.bat`、`stop-server.bat` を **引数なし** で実行することは禁止
- `docker compose --env-file .env ...` (`.env` 直接指定) を実行することは禁止
- `docker compose run --rm sync-init ruby /app/sync.rb ...` を本番 `.env` で実行することは禁止
- `.env` ファイルの内容を読み取ったり、本番の認証情報にアクセスすることは禁止

### 許可される操作

- `./start-server.sh dev` / `./stop-server.sh dev` のように **必ず `dev` 引数付き** で実行する
- `docker compose --env-file .env.dev ...` のように **開発用 env ファイル** を明示する

### スクリプトの安全装置について

`start-server.sh` / `stop-server.sh` は引数なし (本番モード) で呼ばれた場合、
TTY (対話的ターミナル) が存在しない環境 — AI ツール呼び出しを含む — では即座に `exit 1` で終了します。
`.bat` ファイルは "yes" の明示入力を要求するため、自動実行環境では通過できません。

---

## セキュリティに関する注意

- **認証情報は絶対にコミットしないこと。** `.gitignore` は `.env.example` 以外の `.env.*` をすべて除外しています。
- RCON は Docker 内部ネットワーク内にのみ公開されており、外部には公開されていません。
- Minecraft サーバーポート `25565` は公開されています。アクセス制御は `ONLINE_MODE=true` と Tailscale によるプライベートネットワーク設定で行います。
- R2 ロック機構はアトミックではありません (compare-and-swap なし)。1 つのホストのみがサーバーを実行するという運用規則に依存しています。手動ロック解放の手順は README に記載されています。

---

## テスト

```bash
# ログローテーションテストを実行 (サーバーコンテナが起動している必要があります)
bash test/test_log_rotation.sh
```

ユニットテストスイートはありません。インテグレーションテストは Docker Compose スタック全体を起動して手動で行います。

---

## Minecraft サーバー設定

- **バージョン:** 1.20.1 (Forge)
- **メモリ:** 4 GB
- **最大プレイヤー数:** 8
- **ゲームモード:** サバイバル、PVP 有効、飛行許可
- **RCON:** ポート 25575 で有効 (Docker 内部ネットワークのみ)
- **ホワイトリスト:** 無効
- **タイムゾーン:** Asia/Tokyo
- **コマンドブロック:** 無効
- **オンラインモード:** 有効 (正規の Minecraft アカウントが必要)

---

## よくある落とし穴

1. **ロックが残存する:** `sync-shutdown` を実行せずにサーバーがクラッシュした場合、R2 にロックファイルが残ります。
   次回起動前に Docker 経由で `ruby sync.rb unlock` を実行してクリアしてください。

2. **初回起動:** R2 にデータがない状態での初回起動時、サーバーは新規として起動します。
   sync スクリプトは情報メッセージをログ出力し、正常に処理を続行します。

3. **ファイル所有権エラー:** Docker ボリューム内のワールドデータは UID/GID 1000 で所有されている必要があります。
   `sync.rb` の `fix_ownership` メソッドが展開後にこれを処理します。

4. **ログローテーション:** `discord_notify.rb` は inode 追跡を使用してログローテーションを乗り越えます。
   ファイルの位置のみを使用するようにログ監視ロジックを変更しないでください。

5. **環境ファイルの命名:** 起動・停止スクリプトはオプション引数 (例: `dev`) を受け取り、
   `.env.dev` を選択します。`.env.` プレフィックスは不要です。
   例: `./start-server.sh dev` (× `./start-server.sh .env.dev`)
