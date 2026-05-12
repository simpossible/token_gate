# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Token Gate is a local proxy gateway that manages multiple Claude API keys for AI coding tools (Claude Code, Cursor, etc.). It intercepts requests, injects the active API key and model, records token usage, and exposes a management UI.

**Two delivery modes (both ship from this repo):**
- **Go binary (`server/`)** — the daemon itself: API proxy + REST API. Distributed via Homebrew.
- **Flutter desktop app (`app/`)** — native macOS/Windows/Linux app that embeds the Go binary, provides an app-native UI, and shows a system tray with real-time token counts.

## Release Process

Releasing a new version is a single command (no `gh` CLI auth needed — only SSH keys):

```bash
# Release (run from project root)
./scripts/release.sh v0.1.3
```

The script does everything in order:
1. Tags the commit and pushes tag + master to GitHub
2. GitHub Actions (`.github/workflows/release.yml`) triggers automatically: cross-compiles for all five targets, uploads archives + `checksums.txt` as release assets:
   | Platform | Archive |
   |----------|---------|
   | `darwin/arm64` | `.tar.gz` |
   | `darwin/amd64` | `.tar.gz` |
   | `linux/amd64`  | `.tar.gz` |
   | `linux/arm64`  | `.tar.gz` |
   | `windows/amd64`| `.zip`   |
3. Script polls until `checksums.txt` is available (~5-8 min)
4. Fetches CI-built SHA256s from `checksums.txt`
5. Clones `simpossible/homebrew-tap` via SSH, regenerates the formula with the new version and SHA256s, and pushes

**Common pitfalls:**
- Never use `gh release create` locally — the GitHub Actions workflow handles the Release. Local builds produce different SHA256s than CI builds.
- Run the script from the **project root** (where `server/` lives), not from inside `server/`.
- The formula in `homebrew/token_gate.rb` is not the one Homebrew uses — it's a reference copy. The live formula is in the `homebrew-tap` repo (`git@github.com:simpossible/homebrew-tap.git`), updated automatically by the script.
- After release, users install with:
  ```bash
  brew tap simpossible/tap
  brew install token_gate
  ```

## Build Commands

```bash
# Build Go binary
cd server && make build          # → ./token_gate

# Run the server (starts both ports)
./server/token_gate

# Flutter desktop app (compiles Go binary first, then Flutter)
cd server && make app            # → app/build/macos/Build/Products/Release/app.app
```

`make app` does: `make build` → copy `token_gate` binary to `app/assets/bin/` → `flutter build macos`.

## Two-Port Architecture

| Port  | Role              | Handler            |
|-------|-------------------|--------------------|
| 12121 | API proxy         | `internal/proxy`   |
| 12122 | Config REST API   | `internal/api`     |

Both ports bind to `127.0.0.1` only.

## Request Flow Through the Proxy (Port 12121)

```
Claude Code → http://127.0.0.1:12121/claude_code/v1/messages
                │
                ├─ extract agent_type from path prefix ("claude_code")
                ├─ look up active TokenConfig from in-memory cache
                ├─ replace Authorization header with stored api_key
                ├─ replace "model" field in JSON body with stored model
                ├─ forward to config.URL + /v1/messages
                ├─ SSE streaming: flush each line immediately
                └─ parse usage from SSE events → async write to DB
```

The proxy never buffers SSE responses. Usage is extracted from `message_start` and `message_delta` SSE events (looking for `usage.input_tokens` / `usage.output_tokens`).

## In-Memory Cache

`internal/config.ActiveConfigCache` maps `agent_type → *TokenConfig`. It is the hot path for every proxy request. Rules:

- Loaded from DB at startup
- Updated synchronously on every activate/deactivate API call
- Never goes to DB per-request

When a config is activated, the flow is:
1. DB: set `is_active=0` on old active config for the same `agent_type`, set `is_active=1` on new one
2. Cache: `cache.Set(agentType, tokenConfig)`
3. `AgentProcessor.OnActivate(config)` called — for `claude_code` this writes `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY = "placeholder"` into `~/.claude/settings.json`

## Real-Time Event System

Go backend pushes events to Flutter via SSE (Server-Sent Events). `internal/event/event.go` implements an `EventBus` with pub/sub semantics.

**Connection types (separate SSE connections):**

| connType | SSE endpoint | Events | Subscriber |
|----------|-------------|--------|-----------|
| `event` | `GET /api/events?type=event&config_id=xxx` | `usage_new` | ConfigDetail (auto-refresh stats/charts) |
| `event` | `GET /api/events?type=event` | `total_token_change` | TrayService (replaces 5s polling) |
| `log` | `GET /api/events?type=log&config_id=xxx` | `gate_log` | Log panel (real-time request/response log) |

**Event payloads:**

- `gate_log`: `{message: "14:30:01 → POST /v1/messages model=xxx (1234 bytes)"}` — human-readable string, pushed on request received (`→`) and response complete (`←`)
- `usage_new`: `{input_tokens, output_tokens, latency_ms}` — pushed after usage recorded in DB
- `total_token_change`: `{added_in_tokens, added_out_tokens}` — global, for tray title update

**Key design decisions:**

- `HasSubscribers(connType, configID)` is called before constructing/publishing events — zero overhead when no one is listening
- Publish uses non-blocking channel send (`select + default`) — slow clients never block the proxy hot path
- Each subscriber has a buffered channel (cap 64) — events dropped if client can't keep up
- Flutter's `EventService` manages connections by key (`connType_configId`) with auto-reconnect (3s delay)
- ConfigDetail connects to `event` type on mount, disconnects on dispose
- Log panel connects to `log` type on open, disconnects on close
- TrayService connects to `event` type (no config_id) on init, disconnects on dispose

## Extending to New Agent Types

Implement `agent.AgentProcessor` (in `internal/agent/processor.go`) and register it in `main.go`:

```go
type AgentProcessor interface {
    GetType() string                          // e.g. "cursor"
    GetLabel() string                         // e.g. "Cursor"
    OnActivate(config *model.TokenConfig) error
    OnDeactivate(config *model.TokenConfig) error
}
```

Add the new processor to the `processors` slice in `main.go`. No other changes needed — the API and proxy route by `agent_type` string automatically.

## First-Run Auto-Import

On first start (empty DB), `importExistingConfig()` in `main.go` reads `~/.claude/settings.json` and imports any existing API config:

- Reads `ANTHROPIC_AUTH_TOKEN` first (higher priority), falls back to `ANTHROPIC_API_KEY`
- Both values `"placeholder"` (written by Token Gate itself) are explicitly skipped
- `ANTHROPIC_BASE_URL` is skipped if it's already the proxy URL `http://127.0.0.1:12121/claude_code`
- Creates a `token_config` named "default" and activates it for `claude_code`

## Database

SQLite at `~/.token_gate/token_gate.db`. Two tables (as of release_2.0):
- `token_config` — stored API keys and model per named config; includes `agent_type TEXT` and `is_active INTEGER` columns (replaces old `valid_config` table)
- `usage` — append-only request log with token counts

`api_key` is stored in plaintext (local tool, acceptable risk). All API responses mask it to `first4***last4`.

**Schema migration**: On startup `InitSchema` runs `ALTER TABLE token_config ADD COLUMN agent_type` / `is_active` (idempotent), then calls `migrateFromValidConfig()` which reads any legacy `valid_config` rows, writes `agent_type`+`is_active` into `token_config`, and drops the old table. Safe to run on both old and fresh databases.

## Flutter Desktop App Architecture (`app/`)

### Overall relationship

```
[Flutter App] 内嵌 token_gate 二进制 (app/assets/bin/token_gate)
              ↓ 启动时检测 :12122 是否在线，不在线则释放二进制到
                ~/.token_gate/token_gate 并执行（Go 自身 daemonize）
        [Go daemon]  独立运行，与 Flutter 无父子关系
              ↑
        Flutter 通过 HTTP :12122 调用全部 REST API
```

**关键原则：**
- Go daemon 生命周期完全独立，关闭 Flutter 窗口 Go 继续运行
- Flutter 关闭窗口 = 最小化到状态栏（`AppDelegate.applicationShouldTerminateAfterLastWindowClosed` 返回 `false`，`WindowListener.onWindowClose` 调用 `windowManager.hide()`）
- 窗口固定 1000×600，不可 resize，`TitleBarStyle.hidden`

### 目录结构

```
app/
├── lib/
│   ├── main.dart                    # 入口：初始化 window_manager，启动 _Startup 流程
│   ├── models/
│   │   ├── token_config.dart        # TokenConfig (id/name/apiKey/url/model/agentType/isActive)
│   │   ├── agent.dart               # Agent (type/label)
│   │   ├── company.dart             # Company (name/url/models[])
│   │   ├── usage_stats.dart         # UsageStats (requests/inputTokens/outputTokens/avgLatencyMs)
│   │   ├── usage_entry.dart         # UsageEntry + UsageDelta
│   │   └── latency_entry.dart       # LatencyEntry (ttfbMs/createdAtTs)
│   ├── services/
│   │   ├── api_service.dart         # 封装全部 :12122 REST 调用，含 isAlive() 健康检查
│   │   ├── backend_service.dart     # ensureRunning(): 检测→释放二进制→启动→等待就绪(5s)
│   │   └── tray_service.dart        # 状态栏：每5s刷新 ↑xK ↓xK，菜单含打开/退出
│   ├── providers/
│   │   └── providers.dart           # Riverpod providers（见下）
│   └── views/
│       ├── home_view.dart           # 主布局：顶部栏 + 左右分栏，持有 WindowListener
│       ├── config_list.dart         # 左侧 220pt 卡片列表，单击选中/双击 activate
│       ├── config_detail.dart       # 右侧详情：基本信息 + 4 统计数字 + Token 图表 + 延迟图表
│       └── config_form.dart         # 创建/编辑表单（BottomSheet），含厂商预设下拉
├── assets/
│   ├── bin/token_gate               # 编译好的 Go 二进制（make app 自动注入）
│   └── icons/tray_icon.png          # 状态栏图标（22×22）
└── macos/Runner/
    ├── AppDelegate.swift            # applicationShouldTerminateAfterLastWindowClosed → false
    ├── DebugProfile.entitlements    # network.client + files.home-relative ~/.token_gate/
    └── Release.entitlements         # 同上
```

### 启动流程

```
main() → windowManager.ensureInitialized() → 固定窗口参数
       → ProviderScope → TokenGateApp → _Startup.initState()
             ↓
       BackendService.ensureRunning()
             ├─ isAlive() == true → 直接进入 HomeView
             └─ isAlive() == false
                   ↓
             _extractBinary():
               rootBundle.load('assets/bin/token_gate')
               → 写入 ~/.token_gate/token_gate
               → chmod +x (Unix)
                   ↓
             Process.start(detached) → Go 自身 daemonize
                   ↓
             轮询 isAlive()，最多 5s（25×200ms）
                   ↓
             进入 HomeView
```

### Riverpod Providers（`providers/providers.dart`）

| Provider | 类型 | 说明 |
|---|---|---|
| `apiServiceProvider` | `Provider<ApiService>` | 单例 API 客户端 |
| `backendServiceProvider` | `Provider<BackendService>` | daemon 管理 |
| `trayServiceProvider` | `Provider<TrayService>` | 状态栏管理 |
| `selectedAgentTypeProvider` | `StateProvider<String>` | 当前选中 agent 类型（默认 `claude_code`） |
| `selectedConfigIdProvider` | `StateProvider<int?>` | 当前选中配置 ID |
| `agentsProvider` | `FutureProvider<List<Agent>>` | GET /api/agents |
| `configsProvider` | `AsyncNotifierProvider<ConfigsNotifier, List<TokenConfig>>` | 按 agentType 过滤的配置列表，watch `selectedAgentType` 自动刷新 |
| `usageStatsProvider(id)` | `FutureProvider.family<UsageStats, int>` | GET /api/configs/:id/usage |
| `usagesProvider(id)` | `FutureProvider.family<List<UsageEntry>, int>` | GET /api/usages?config_id=id |
| `latencyProvider(id)` | `FutureProvider.family<List<LatencyEntry>, int>` | GET /api/latency/latest |
| `companiesProvider` | `FutureProvider<List<Company>>` | GET /api/companies |

`ConfigsNotifier` 提供 `activate(id)` / `deactivate(id)` / `delete(id)` / `reload()` 方法，调用后自动刷新列表。

### UI 布局（1000×600 固定）

```
┌─────────────────────────────────────────────────────────────────┐
│  顶部栏 (52pt)：TokenGate Logo │ Agent下拉 │ [+]按钮             │
├──────────(220pt)───┬────────────────────────────────────────────┤
│  ConfigList        │  ConfigDetail                              │
│  卡片列表           │  2.2.1 基本信息（InfoChip 横排）             │
│  单击→选中          │  2.2.2 统计数字（4个StatCard）               │
│  双击→activate      │  2.2.3 Token图表（折线/柱状切换，fl_chart）  │
│  生效中→紫色badge   │  2.2.4 延迟图表（折线，TTFB）               │
└────────────────────┴────────────────────────────────────────────┘
```

无选中配置时右侧显示空状态（大"创建新配置"按钮）。创建/编辑通过 `DraggableScrollableSheet` 从底部滑入。

### macOS 特殊配置

- **Entitlements（非 App Store 分发）**：`com.apple.security.network.client`（调 127.0.0.1）+ `temporary-exception.files.home-relative-path.read-write` 允许读写 `~/.token_gate/`
- **不上 App Store 原因**：沙盒会阻断写 `~/.claude/settings.json` 和绑定固定端口（12121/12122）

## Company/Vendor List (`internal/company`)

The form for creating/editing a token config shows a dynamic list of vendor presets (name, API URL, and available models) fetched from `GET /api/companies`.

### Data flow
1. **Embedded default**: `server/internal/company/company.json` is embedded via `//go:embed` and used on first run.
2. **Disk cache**: On startup, `company.Manager` reads `~/.token_gate/company.json` if it exists (written by a prior refresh).
3. **Background refresh**: Every call to `GET /api/companies` triggers a silent goroutine that fetches the latest JSON from GitHub raw URL and saves it to disk:
   ```
   https://github.com/simpossible/token_gate/raw/refs/heads/master/server/internal/company/company.json
   ```
4. The API response always returns the current in-memory data (no blocking wait for the refresh).

### JSON schema
```json
{
  "list": [
    { "name": "智谱 GLM (全球)", "url": "https://api.z.ai/api/anthropic", "models": ["glm-5", "glm-5.1"] }
  ]
}
```

### Updating the vendor list
Edit `server/internal/company/company.json` and commit to master. Existing running instances will pick up the change on the next page open (background refresh).

## Key Gotchas

- **`agent_type` is immutable after creation**: The backend validates `agent_type` on create (must be a registered processor type) but ignores it on update. The frontend enforces this with a disabled field in edit mode.
- **One active config per agent type**: `ActivateTokenConfig` atomically deactivates any existing active config for the same `agent_type` before activating the new one — both in DB (transaction) and via `OnDeactivate`/`OnActivate` processor hooks.
- **`GET /api/configs` vs `GET /api/configs/:id`**: Both return plain `TokenConfig` (with `agent_type` and `is_active`). The list endpoint accepts `?agent_type=` to filter. `ConfigWithAgents` and `active_agents` no longer exist.
- **CORS**: The API server (port 12122) returns `Access-Control-Allow-Origin: *` headers for cross-origin requests.
- **Flutter `assets/bin/token_gate` must exist before `flutter build`**: `make app` handles this automatically, but running `flutter build macos` directly without the binary will fail at runtime (not compile time — `rootBundle.load` throws at asset extraction).
- **Flutter `DropdownButtonFormField.value` is deprecated in Flutter 3.33+**: use `initialValue` instead.
- **`ConfigsNotifier` reacts to `selectedAgentTypeProvider`**: because `build()` calls `ref.watch(selectedAgentTypeProvider)`, switching agent type automatically triggers a full list reload — no manual wiring needed.

## Cross-Platform Support

The binary targets macOS, Linux, and Windows. Platform-specific daemon/signal code is split into two files via build tags:

| File | Build tag | Responsibility |
|------|-----------|----------------|
| `server/daemon_unix.go` | `//go:build !windows` | `Setsid=true` for session detach, `SIGTERM`/`Signal(0)` for process control |
| `server/daemon_windows.go` | `//go:build windows` | `CREATE_NO_WINDOW` flag for detach, `OpenProcess`+`GetExitCodeProcess` for liveness, `proc.Kill()` for termination |

Four helper functions are declared in both files (one wins at compile time):

```go
isProcessAlive(proc *os.Process) bool   // check if PID is still running
terminateProcess(proc *os.Process) error // graceful stop (SIGTERM on Unix, Kill on Windows)
setDaemonProcess(cmd *exec.Cmd)          // detach from terminal before exec
registerShutdownSignals(ch chan os.Signal) // SIGTERM+SIGINT on Unix, Interrupt on Windows
```

`main.go` imports neither `syscall` nor `os/signal` directly — all platform-specific calls go through these helpers.

**`~/.claude/settings.json` path**: `os.UserHomeDir()` + `.claude/settings.json` works on all three platforms (Claude Code CLI follows Unix dotfile convention even on Windows).

## attendion
每次重要的功能设计变更要更新到项目知识文档中
