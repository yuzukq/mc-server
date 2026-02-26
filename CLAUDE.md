# CLAUDE.md — AI Assistant Guide for mc-server

## Project Overview

This repository is a **Dockerized Minecraft server management system** that enables
multiple hosts to share a single Minecraft world stored on Cloudflare R2 object storage.
Key features include: distributed hosting with a pessimistic locking mechanism to prevent
concurrent launches, automatic world data sync on startup/shutdown, Discord event
notifications, and in-game host display via a Minecraft bossbar.

**Language stack:** Ruby 3.2 (primary), Bash/Batch (orchestration), MCFunction (datapack)

---

## Repository Structure

```
mc-server/
├── .github/
│   └── pull_request_template.md   # PR template (Japanese, review prefixes defined here)
├── datapack/
│   └── host_bossbar/              # Minecraft datapack for bossbar support
│       ├── pack.mcmeta
│       └── data/
│           ├── minecraft/tags/functions/load.json
│           └── hostbossbar/functions/
│               ├── load.mcfunction
│               └── tick.mcfunction
├── docker/
│   └── ruby/
│       └── Dockerfile             # Custom Ruby image with aws-sdk-s3 gem
├── scripts/
│   ├── lib/
│   │   └── rcon_client.rb         # Shared RCON protocol implementation
│   ├── bossbar.rb                 # Displays host name in-game via bossbar
│   ├── discord_notify.rb          # Sends server/player events to Discord
│   ├── measure-performance.sh     # TPS/MSPT/CPU/memory metrics via RCON
│   └── sync.rb                    # World data sync with Cloudflare R2
├── test/
│   └── test_log_rotation.sh       # Log rotation detection test
├── .env.example                   # Template for environment configuration
├── .gitignore
├── README.md                      # Full Japanese documentation with diagrams
├── compose.yml                    # Docker Compose service definitions
├── start-server.sh / start-server.bat   # Cross-platform server start scripts
└── stop-server.sh  / stop-server.bat    # Cross-platform server stop scripts
```

---

## Docker Services

Defined in `compose.yml`. Services run in dependency order:

| Service | Container | Purpose | Lifecycle |
|---|---|---|---|
| `sync-init` | `mc_sync_init` | Acquires R2 lock, downloads world data | Runs once before `server` starts |
| `server` | `mc_server` | Minecraft server (Forge 1.20.1, 4 GB RAM) | `restart: unless-stopped` |
| `sync-shutdown` | `mc_sync_shutdown` | Uploads world data, releases R2 lock | Runs once on shutdown (profile: `shutdown`) |
| `bossbar-manager` | `mc_bossbar` | Displays host name in-game via RCON | Runs once after server starts |
| `discord-notify` | `mc_discord_notify` | Tails server logs, notifies Discord | Runs alongside server |

`sync-shutdown` is gated behind the `shutdown` profile and is explicitly triggered by
the stop scripts rather than running automatically.

---

## Environment Configuration

Copy `.env.example` to `.env` and fill in all values before starting.

| Variable | Description |
|---|---|
| `R2_ACCOUNT_ID` | Cloudflare account ID |
| `R2_ACCESS_KEY_ID` | R2 API access key |
| `R2_SECRET_ACCESS_KEY` | R2 API secret key |
| `R2_BUCKET_NAME` | Bucket name for world data |
| `R2_ENDPOINT` | `https://<account_id>.r2.cloudflarestorage.com` |
| `LOCAL_DATA_DIR` | Local mount path for world data (default: `./data`) |
| `HOST_DISPLAY_NAME` | Host name shown to players in-game (unique per host) |
| `RCON_PASSWORD` | Minecraft RCON password (default: `minecraft`) |
| `DISCORD_WEBHOOK_URL` | Discord webhook URL for event notifications |

For development/testing, create `.env.dev` (already gitignored) and run scripts with the
`dev` argument to use it instead.

**Important:** Never commit `.env` or any file containing real credentials.
The `.gitignore` excludes `.env` and `.env.*` (except `.env.example`).

---

## Development Workflow

### Starting and Stopping the Server

**Linux/Mac:**
```bash
./start-server.sh        # uses .env
./start-server.sh dev    # uses .env.dev
./stop-server.sh
./stop-server.sh dev
```

**Windows:**
```batch
start-server.bat
start-server.bat dev
stop-server.bat
```

The start script automatically builds the custom Ruby Docker image on first run.

### Useful Docker Commands

```bash
# Follow server logs
docker logs -f mc_server

# Manual start/stop (without sync)
docker compose up -d
docker compose down

# Check/release the R2 lock (if server crashed without unlocking)
docker compose run --rm sync-init ruby /app/sync.rb check-lock
docker compose run --rm sync-init ruby /app/sync.rb unlock

# Force data download or upload
docker compose run --rm sync-init ruby /app/sync.rb download
docker compose run --rm sync-init ruby /app/sync.rb upload
```

### sync.rb CLI Commands

`scripts/sync.rb` accepts these subcommands:

| Command | Description |
|---|---|
| `init` | Acquire lock + download world data (run before server start) |
| `shutdown` | Upload world data + release lock (run after server stop) |
| `download` | Download only |
| `upload` | Upload only |
| `lock` | Acquire lock only |
| `unlock` | Release lock only |
| `check-lock` | Print current lock status |

---

## Key Scripts and Their Design

### `scripts/sync.rb` — World Data Synchronization

- Class: `R2Sync`
- Uses `aws-sdk-s3` gem to interact with Cloudflare R2 (S3-compatible API)
- **Lock mechanism:** Stores a `server.lock` JSON file in R2 containing hostname,
  timestamp, and PID. Prevents two hosts from running the server simultaneously.
- **Data format:** World data is compressed as `server-data.tar.gz` with
  `--owner=1000 --group=1000` to ensure consistent file ownership inside Docker.
- Validates all required env vars on startup; exits with code 1 if any are missing.

### `scripts/discord_notify.rb` — Discord Notifications

- Classes: `DiscordWebhook`, `LogWatcher`, `DiscordNotifier`
- Watches `./data/logs/latest.log` in real time using inode tracking to handle log
  rotation (file is replaced rather than truncated).
- Detects patterns: server start/stop, player join/leave.
- Sends color-coded Discord embeds (blue=online, green=join, orange=leave, red=offline).
- Registers SIGTERM/SIGINT handlers for graceful shutdown.

### `scripts/bossbar.rb` — In-Game Host Display

- Class: `BossbarManager`
- Connects to the Minecraft server via RCON after it finishes loading.
- Retries connection (configurable via `MAX_RETRIES` and `RETRY_INTERVAL` env vars).
- Runs Minecraft commands to create and display a bossbar showing `HOST_DISPLAY_NAME`.

### `scripts/lib/rcon_client.rb` — Shared RCON Library

- Class: `RconClient`
- Custom implementation of the RCON protocol over TCP.
- Custom exceptions: `AuthenticationError`, `ConnectionError`.
- Handles binary packet framing and UTF-8 encoding.
- Shared by both `bossbar.rb` and `discord_notify.rb`.

---

## Code Conventions

- **Frozen string literals:** Every Ruby file begins with `# frozen_string_literal: true`.
- **Class-based architecture:** Each script exposes one or more focused classes.
- **Comments are in Japanese** — this is intentional and should be preserved.
- **Emoji in console output** — used throughout for visual status clarity; preserve this style.
- **Error handling:** Use custom exception classes for domain errors; rescue
  `Aws::S3::Errors::ServiceError` for R2 operations.
- **No test framework:** The single test (`test/test_log_rotation.sh`) is a bash script
  that exercises the Docker environment directly.
- **Do not use `unless` for negated boolean conditions** — the codebase uses `if !bool`
  style (see commit `b324b63`).
- **Ownership:** All world data files must be owned by UID/GID 1000 inside Docker.

---

## Pull Request Conventions

PRs follow the template in `.github/pull_request_template.md`.

- Written in **Japanese**
- Sections: 概要 (Overview), 背景・動機 (Background), 新規追加ファイル (New Files),
  変更内容 (Changes), 技術的な判断 (Technical Decisions), スクリーンショット (Screenshots),
  レビューに関して (Review Notes)
- **Review comment prefixes:**
  - `[must]` — required change
  - `[imo]` — opinion, not mandatory
  - `[nits]` — nitpick
  - `[ask]` — question
  - `[fyi]` — informational

**Review focus areas:** naming consistency, security concerns, performance impact,
proper method responsibility separation, typos in variable names and comments.

---

## Security Notes

- **Never commit credentials.** The `.gitignore` excludes all `.env.*` files except
  `.env.example`.
- RCON is only exposed within the Docker internal network (not published externally).
- The Minecraft server port `25565` is published; access control is via `ONLINE_MODE=true`
  and Tailscale for private network setups.
- The R2 lock mechanism is not atomic (no compare-and-swap); it relies on the convention
  that only one host runs the server at a time. Manual lock release is documented in
  the README.

---

## Testing

```bash
# Run the log rotation test (requires a running server container)
bash test/test_log_rotation.sh
```

There is no unit test suite. Integration testing is manual by running the full Docker
Compose stack.

---

## Minecraft Server Configuration

- **Version:** 1.20.1 (Forge)
- **Memory:** 4 GB
- **Max players:** 8
- **Game mode:** Survival, PVP enabled, flight allowed
- **RCON:** Enabled on port 25575 (internal Docker network only)
- **Whitelist:** Disabled
- **Timezone:** Asia/Tokyo
- **Command blocks:** Disabled
- **Online mode:** Enabled (requires valid Minecraft account)

---

## Common Pitfalls

1. **Stale lock:** If the server crashes without running `sync-shutdown`, the R2 lock
   file remains. Run `ruby sync.rb unlock` via Docker to clear it before the next start.

2. **First run:** On first start with no data in R2, the server boots fresh. The sync
   script logs an info message and continues normally.

3. **File ownership errors:** World data inside the Docker volume must be owned by
   UID/GID 1000. The `fix_ownership` method in `sync.rb` handles this after extraction.

4. **Log rotation:** `discord_notify.rb` uses inode tracking (not file name) to survive
   Minecraft's log rotation. Do not change the log watching logic to use file position
   only.

5. **Environment file naming:** The start/stop scripts accept an optional argument
   (e.g., `dev`) that selects `.env.dev`. Do not pass the `.env.` prefix — just the
   suffix (e.g., `./start-server.sh dev`, not `./start-server.sh .env.dev`).
