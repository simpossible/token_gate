# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Token Gate is a local proxy gateway that manages multiple Claude API keys for AI coding tools (Claude Code, Cursor, etc.). It intercepts requests, injects the active API key and model, records token usage, and exposes a management UI.

**Two delivery modes (both ship from this repo):**
- **Go binary (`server/`)** — the daemon itself: API proxy + REST API. Distributed via Homebrew.
- **Flutter desktop app (`app/`)** — native macOS/Windows/Linux app that embeds the Go binary, provides an app-native UI, and shows a system tray with real-time token counts.

## Release Process

### macOS

Releasing a new version is a single command (no `gh` CLI — only SSH keys + GitHub PAT):

```bash
# Prerequisites (set once):
export TOKEN_GATE_GITHUB_TOKEN="ghp_xxxx"      # GitHub PAT (repo scope)
export TOKEN_GATE_APPLE_ID="..."                # Apple ID for notarization
export TOKEN_GATE_APPLE_PASSWORD="xxxx-xxxx"    # App-specific password
export TOKEN_GATE_APPLE_TEAM_ID="5X939PFV35"

# Release (run from project root)
./scripts/release.sh v0.2.1
```

The script does everything in order:
1. Calls `build_dmg.sh` to build the DMG locally (Go binary → Flutter → sign → notarize)
2. Tags the commit and pushes tag + master to GitHub via SSH
3. Creates a GitHub Release via API and uploads the DMG
4. Clones `simpossible/homebrew-tap` via SSH, updates the Cask with new version + SHA256, and pushes

**Common pitfalls:**
- **Never use `gh` CLI for releases** — the project uses `git tag` + `git push` + GitHub API (via `TOKEN_GATE_GITHUB_TOKEN`). No `gh auth` needed.
- The DMG must be built locally (requires Developer ID Application certificate in Keychain). Cannot be built in CI because code signing certificates are not available there.
- The app inside the DMG is `TokenGate.app` (set via `PRODUCT_NAME` in `AppInfo.xcconfig`). The Cask references `app "TokenGate.app"`.
- After release, users install with:
  ```bash
  brew tap simpossible/tap
  brew install --cask token-gate
  ```

### Windows

Windows releases use Inno Setup to create an installer with custom installation path support.

```batch
REM Prerequisites:
REM 1. GitHub PAT (set once):
REM    set TOKEN_GATE_GITHUB_TOKEN=ghp_xxxx
REM 2. Inno Setup Compiler:
REM    winget install JRSoftware.InnoSetup

REM Release (run from project root)
.\scripts\release.bat v0.2.1
```

The script does everything in order:
1. Calls `build_installer.bat` to build the installer locally (Go binary → Flutter → Inno Setup)
2. Tags the commit and pushes tag + master to GitHub via SSH
3. Creates a GitHub Release via API and uploads the installer

**Common pitfalls:**
- Inno Setup must be installed and `iscc` in PATH
- The installer must be built on Windows (Inno Setup is Windows-only)
- Users download `TokenGate-{version}-setup.exe` and run it to install

### macOS 签名踩坑（build_dmg.sh 的设计原因）

**为什么不用 Xcode 正常签名：** Flutter 的 `xcode_backend.dart` 会用 Runner target 的签名身份去签所有 framework，强制连 Apple timestamp 服务。代理环境下 timestamp 服务不稳定，导致构建随机失败。

**实际方案：**
1. Flutter 构建时临时用 ad-hoc 签名（`CODE_SIGN_IDENTITY = "-"`），构建完恢复 `project.pbxproj`
2. 构建后手动签名，**顺序必须 inside-out**：
   - 先签 Go 二进制（`Contents/Resources/token_gate`）→ `--options runtime --timestamp`
   - 再签 `App.framework`
   - 最后 `--deep` 签主 bundle + entitlements
3. **不能只用 `--deep`**：它不会给 `Contents/Resources/` 里的独立二进制加 hardened runtime，公证会拒绝

**entitlements 必须显式设 `get-task-allow = false`**（`Release.entitlements`），否则公证报错——Xcode 在 Debug 构建时会自动加这个 key，Release 构建残留就会被 Apple 拒绝。

### Windows 安装器设计（installer.iss）

**为什么用 Inno Setup：** 免费、开源、功能完善，支持自定义安装路径、创建桌面快捷方式、完整卸载程序。

**实际方案：**
1. 使用 `[Setup]` 段配置基本信息（AppId、版本、默认安装目录）
2. 默认安装路径：`{autopf}\TokenGate`（`{autopf}` 自动映射到 Program Files，x64 下为 Program Files (x86)）
3. 支持 3 种语言：英语、简体中文、日语（`[Languages]` 段）
4. 可选创建桌面快捷方式和快速启动图标（`[Tasks]` 段，默认不勾选）
5. 卸载时删除用户数据目录（`{localappdata}\TokenGate` 和 `{userappdata}\.token_gate`）

**安装前处理（`[Code]` 段）：**
- `PrepareToInstall()` 会调用 `taskkill /F /IM TokenGate.exe` 关闭正在运行的实例
- 避免安装时文件被占用导致失败

## Build Commands

```bash
# Build Go binary
cd server && make build          # → ./token_gate

# Run the server (starts both ports)
./server/token_gate

# Flutter desktop app — macOS
cd server && make app            # → app/build/macos/Build/Products/Release/TokenGate.app

# Flutter desktop app — Windows (must run on a Windows machine)
cd server && make windows-app   # → app/build/windows/x64/runner/Release/

# Windows installer (requires Inno Setup)
cd server && make windows-installer VERSION=2.0.0  # → build/TokenGate-2.0.0-setup.exe
```

`make app` does: `make build` → copy `token_gate` binary to `app/assets/bin/` → `flutter build macos`.

`make windows-app` does: cross-compile `GOOS=windows` → copy `token_gate.exe` to `app/assets/bin/` → `flutter build windows`. The Go cross-compile step can run on macOS, but `flutter build windows` must run on Windows.

`make windows-installer` does: `make windows-app` → compile installer with Inno Setup (`iscc`). Inno Setup must be installed (Windows-only).

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
| `log` | `GET /api/events?type=log&config_id=xxx` | `gate_debug` | Debug inspector (structured request lifecycle events) |

**Event payloads:**

- `gate_log`: `{message: "..."}` — pushed multiple times per request:
  1. Request summary line: `"14:30:01 → POST /v1/messages model=xxx (1234 bytes)"`
  2. Request body: full pretty-printed JSON
  3. SSE streaming: each `data:` line pushed individually in real-time
  4. Non-SSE response: full pretty-printed response JSON
  5. Response summary line: `"14:30:03 ← ↑185 ↓79 1569ms streaming"`
- `gate_debug`: structured event with `kind` field — published at each proxy lifecycle stage:
  1. `request_start` — method, path, target_url, agent_type, model
  2. `request_headers` — client request headers + forwarded headers (Authorization NOT masked — local tool)
  3. `request_body` — pretty-printed request JSON body
  4. `response_headers` — status code + response headers from upstream
  5. `response_chunk` — each SSE `data:` line (streaming responses)
  6. `request_end` — latency/ttfb, usage (input/output tokens), completed flag
  - Each event carries `req_id` (short random ID) and `ts_ms` for correlation
  - Flutter `DebugInspectorNotifier` aggregates events by `req_id` into `DebugRequestEntry` objects
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
│   │   ├── event_service.dart       # SSE 客户端：手动解析 SSE 格式，按 key 管理连接，自动重连(3s)
│   │   ├── backend_service.dart     # ensureRunning(): 检测→释放二进制→启动→等待就绪(5s)
│   │   ├── update_service.dart      # 版本更新检查：调用远端 /api/new_version 接口
│   │   └── tray_service.dart        # 状态栏：监听 total_token_change 事件更新 ↑xK ↓xK
│   ├── providers/
│   │   ├── providers.dart           # Riverpod providers（见下）
│   │   ├── debug_inspector_provider.dart # DebugInspectorNotifier：聚合 gate_debug 事件为 RequestEntry
│   │   └── update_provider.dart     # 版本更新：deviceId 生成/持久化 + newVersionProvider + checkForUpdate
│   └── views/
│       ├── home_view.dart           # 主布局：顶部栏 + 左右分栏 + overlay panels，持有 WindowListener
│       ├── config_list.dart         # 左侧 220pt 卡片列表，单击选中/双击 activate
│       ├── config_detail.dart       # 右侧详情：监听 usage_new 实时刷新 + 调试按钮
│       ├── config_form.dart         # 创建/编辑表单（BottomSheet），含厂商预设下拉
│       ├── debug_inspector_overlay.dart # Network调试面板：三栏布局，请求列表/详情/RawLog
│       └── proxy_panel.dart         # 代理设置面板
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
| `eventServiceProvider` | `Provider<EventService>` | SSE 客户端管理（按 key 管理连接，自动重连） |
| `backendServiceProvider` | `Provider<BackendService>` | daemon 管理 |
| `trayServiceProvider` | `Provider<TrayService>` | 状态栏管理（监听 total_token_change 事件） |
| `selectedAgentTypeProvider` | `StateProvider<String>` | 当前选中 agent 类型（默认 `claude_code`） |
| `selectedConfigIdProvider` | `StateProvider<int?>` | 当前选中配置 ID |
| `agentsProvider` | `FutureProvider<List<Agent>>` | GET /api/agents |
| `configsProvider` | `AsyncNotifierProvider<ConfigsNotifier, List<TokenConfig>>` | 按 agentType 过滤的配置列表，watch `selectedAgentType` 自动刷新 |
| `usageStatsProvider(id)` | `FutureProvider.family<UsageStats, int>` | GET /api/configs/:id/usage |
| `usagesProvider(id)` | `FutureProvider.family<List<UsageEntry>, int>` | GET /api/usages?config_id=id |
| `latencyProvider(id)` | `FutureProvider.family<List<LatencyEntry>, int>` | GET /api/latency/latest |
| `companiesProvider` | `FutureProvider<List<Company>>` | GET /api/companies |
| `debugInspectorProvider(configId)` | `StateNotifierProvider.family<DebugInspectorNotifier, DebugInspectorState, String>` | 聚合 gate_debug 事件为请求列表（max 200），订阅 `log` SSE |

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

### Debug Inspector（Network 调试面板）

类似 Chrome DevTools Network 面板，通过 ConfigDetail 头部的虫子图标（`Icons.bug_report_outlined`）打开。覆盖 ConfigDetail 区域（`Positioned(top:52, left:220, right:0, bottom:0)`）。

**三栏布局：**

| 区域 | 宽度 | 内容 |
|------|------|------|
| area-1（请求列表） | 240pt，可拖拽 150-400 | 每个请求显示 method badge + path + status（颜色编码）+ latency |
| area-2（详情） | Expanded | 三个 tab：Header（key-value 表格）/ Payload（request body）/ Response（SSE 流式追加，自动滚动） |
| area-3（Raw Log） | 280pt，可隐藏/可拖拽 150-500 | 复用 `gate_log` 的原始文本流，深色主题，显示/隐藏状态通过 `SharedPreferences` 记忆 |

**数据流：**

```
Go proxy lifecycle → publishDebug(gate_debug, kind=request_start|request_headers|...)
  → SSE /api/events?type=log&config_id=xxx
  → Flutter EventService → DebugInspectorNotifier._onEvent()
  → 按 req_id 聚合为 DebugRequestEntry（max 200）
```

**搜索功能：**
- `Cmd+F` / `Ctrl+F` 快捷键或点击搜索图标唤起搜索栏
- `Esc` 关闭搜索
- 搜索时所有 tab 内容用 `RichText` + 黄色高亮（`Color(0xFFFFF3B0)`）显示匹配
- Header tab 搜索时切换为纯文本视图（key: value 格式）
- Raw Log 每行也支持搜索高亮
- 显示当前 tab 匹配数（`_searchMatchCount`）

**关键文件：**
- `server/internal/proxy/proxy.go` — `publishDebug()` 在请求生命周期各阶段发送结构化事件
- `app/lib/providers/debug_inspector_provider.dart` — `DebugInspectorNotifier` 聚合事件，维护 `entries` / `rawLogs` 列表
- `app/lib/views/debug_inspector_overlay.dart` — 三栏 UI，`HardwareKeyboard` 监听 Cmd+F
- `app/lib/views/config_detail.dart` — `onOpenDebug` 回调 + 虫子图标按钮
- `app/lib/views/home_view.dart` — overlay `Positioned` 容器

### macOS 特殊配置

- **Entitlements（非 App Store 分发）**：`com.apple.security.network.client`（调 127.0.0.1）+ `temporary-exception.files.home-relative-path.read-write` 允许读写 `~/.token_gate/`
- **不上 App Store 原因**：沙盒会阻断写 `~/.claude/settings.json` 和绑定固定端口（12121/12122）

### Windows 特殊配置

Flutter 层的三处 Windows 适配（不能照搬 macOS 写法）：

1. **Go 二进制路径** (`backend_service.dart` `_bundleBinaryPath()`)：macOS 用 app bundle 路径 `Contents/Resources/token_gate`；Windows 用 **EXE 同级目录** `<dir>\token_gate.exe`（CMake install 规则负责将其复制过去）

2. **托盘标题** (`tray_service.dart`)：macOS 用 `trayManager.setTitle(text)` 在菜单栏图标旁显示文字；Windows 不支持 `setTitle`，必须用 `trayManager.setToolTip(text)`，否则静默失败

3. **关窗隐藏到托盘** (`home_view.dart`)：macOS 由 `AppDelegate.swift` 在原生层拦截；Windows 必须在 `initState()` 调用 `windowManager.setPreventClose(true)`，否则关窗事件到不了 Dart 层的 `onWindowClose`，进程直接退出

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

## Version Update Check System

### Remote Service (`token_gate_remote/`)

A standalone Go HTTP service deployed separately from Token Gate. Provides version checking and DAU statistics.

**Port**: 12124 (configurable via `PORT` env var)

**Endpoints**:
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/new_version?device_id=xxx&platform=mac` | GET | Returns latest version for platform, records device activity for DAU |
| `/api/stats/dau` | GET | Returns today's DAU count (unique device_ids) |

**Config file** (`config.json` in working directory):
```json
{
  "mac": { "new_version": "2.0.0" },
  "windows": { "new_version": "2.0.0" },
  "linux": { "new_version": "2.0.0" }
}
```
Reloaded every 5 minutes. Edit and save to update versions across all running instances.

**DAU tracking**: SQLite database (`token_gate_remote.db`) with `device_activity` table (device_id, platform, date). Uses `INSERT OR IGNORE` for idempotent writes.

### Flutter App Side

- **Device ID**: Generated as UUID v4 on first launch, persisted via `shared_preferences` (key: `token_gate_device_id`)
- **Update check**: `checkForUpdate()` in `update_provider.dart` calls remote service, compares with `package_info_plus` version
- **Timing**: Checked once on startup, then every hour via `Timer.periodic` in `HomeView`
- **UI**: Purple "有新版本" badge in top bar (between spacer and agent dropdown), controlled by `newVersionProvider`
- **Windows UI**: 28pt title bar with close button (purple theme, top-right corner) + tray icon support
  - Title bar: `Padding(top: 0)` for Windows, `Padding(top: 28)` for macOS (reserved for OS traffic lights)
  - Close button: Top-right 14×14 × icon (`Icons.close`, `#9CA3AF` gray), calls `windowManager.hide()`
  - Tray icon: Uses `.ico` format on Windows (16/32/48/256 sizes), PNG on macOS
  - Tray right-click: `onTrayIconRightMouseDown()` → `trayManager.popUpContextMenu()` to show menu (Windows fix)

### Provider Setup (`update_provider.dart`)

| Provider | Type | Description |
|----------|------|-------------|
| `updateServiceProvider` | `Provider<UpdateService>` | HTTP client for remote version API |
| `deviceIdProvider` | `FutureProvider<String>` | UUID persisted in shared_preferences |
| `newVersionProvider` | `StateProvider<String?>` | null = no update, string = new version available |

## Daemon BuildID Version Check

When the app upgrades, the old Go daemon may still be running. Flutter now checks the daemon's buildID and restarts it if mismatched.

**How it works:**
1. Go binary compiled with `-ldflags "-X main.buildID=$(git rev-parse --short HEAD)"` — injects git short hash
2. Go API exposes `GET /api/version` returning `{"build_id": "c88eadb"}`
3. Makefile writes the same buildID to `app/assets/bin/build_id.txt` at build time
4. Flutter `BackendService.ensureRunning()` reads `rootBundle.loadString('assets/bin/build_id.txt')` as expected buildID
5. If daemon is alive but buildID doesn't match → `pkill -f token_gate.*--daemon` → start new binary

**Key files:**
- `server/main.go` — `var buildID = "dev"` (overridden at compile time)
- `server/internal/api/api.go` — `API.buildID` field, `/api/version` endpoint
- `server/Makefile` — all `go build` commands pass `-ldflags`, `build_id.txt` written for `app` and `windows-app` targets
- `app/lib/services/backend_service.dart` — `_loadExpectedBuildID()`, buildID comparison in `ensureRunning()`
- `app/lib/services/api_service.dart` — `getBuildID()` method

## Config List Sorting (last_used_at)

Configs are sorted by: active first → `last_used_at` DESC → `created_at` DESC.

- `token_config.last_used_at` — `INTEGER NOT NULL DEFAULT 0`, millisecond Unix timestamp
- Updated on `ActivateTokenConfig` (immediate) and `RecordUsage` (per request)
- Flutter sort in `config_list.dart`: `_parseCreatedTs()` fallback parses RFC 3339 `created_at` string to ms
- Backend `ORDER BY`: `COALESCE(NULLIF(last_used_at, 0), CAST(strftime('%s', created_at) * 1000 AS INTEGER)) DESC`

## ConfigDetail State Lifecycle

`ConfigDetail` is a `ConsumerStatefulWidget`. When the user switches selected config, Flutter may reuse the State object (same runtimeType, no key). The SSE subscription in `initState()` won't re-run.

**Solution:** `didUpdateWidget` compares `oldWidget.config.id != widget.config.id`, and if changed:
1. Cancels old SSE subscription
2. Disconnects old SSE connection (`event_{oldId}`)
3. Calls `_subscribeEvents()` with new configId
4. Invalidates `usageStatsProvider` and `usagesProvider` to fetch latest data

## Proxy Settings

Global HTTP proxy configuration for routing outgoing API requests through a proxy server.

### Storage

- `app_setting` table in SQLite (`~/.token_gate/token_gate.db`) — key-value store
- Proxy config stored as JSON under key `proxy_config`: `{"host":"127.0.0.1","port":"7890","enabled":true}`
- Read from DB per-request (no in-memory cache) — settings take effect immediately after save

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/proxy` | GET | Returns current proxy config `{"host":"","port":"","enabled":false}` |
| `/api/proxy` | PUT | Updates proxy config, validates host+port when enabled |

### How Proxy is Applied

1. **Proxy handler** (`server/internal/proxy/proxy.go`): `newHTTPClient()` reads proxy config from DB on every request. When enabled, creates `http.Transport{Proxy: http.ProxyURL(proxyURL)}` where `proxyURL = "http://" + host + ":" + port`.
2. **Company refresh** (`server/internal/company/company.go`): GitHub fetch also respects proxy settings via the same DB read pattern.

### Flutter UI

- "代理设置" menu item in the More popup menu (3rd item after 创建配置 and 查看日志)
- `ProxyPanel` slides in as a `Positioned(top: 52, left: 220, right: 0, bottom: 0)` overlay in the Stack
- Contains: enable/disable Switch, host + port TextFields, save button
- Uses `proxyConfigProvider` (FutureProvider) for initial load, invalidates on save
- Style matches ConfigDetail: white bg, indigo accent `0xFF6366F1`, border radius 10, `EdgeInsets.all(24)`

### Key Files

- `server/internal/model/model.go` — `ProxyConfig` struct (host, port, enabled)
- `server/internal/database/database.go` — `app_setting` table, `GetProxyConfig`/`SetProxyConfig`
- `server/internal/api/api.go` — `GET/PUT /api/proxy`
- `server/internal/proxy/proxy.go` — `newHTTPClient()` with proxy transport
- `server/internal/company/company.go` — proxy-aware `refresh()`
- `app/lib/models/proxy_config.dart` — Flutter model
- `app/lib/views/proxy_panel.dart` — Proxy settings panel UI

## Release Changelog

### v0.2.6
- **Feat:** Network 调试面板（Debug Inspector）— Chrome DevTools 风格的请求检查器
  - 三栏布局：请求列表 / 详情（Header·Payload·Response） / Raw Log（默认显示，比例 44:100:80）
  - 可拖拽分栏调整宽度，Raw Log 面板可隐藏/显示（状态持久化）
  - Go 端新增 `gate_debug` 结构化 SSE 事件（request_start/headers/body/response_headers/chunk/end）
  - Flutter 端 `DebugInspectorNotifier` 聚合事件为 `DebugRequestEntry`，支持 SSE 流式追加
  - 独立搜索：Detail 和 Raw Log 各自独立的搜索栏，Cmd+F 根据鼠标所在区域激活
  - 搜索导航：Enter 键逐个跳转匹配项，显示 `a / b` 计数，当前匹配橙色高亮
  - Raw Log 支持跨行选择和 Cmd+A（SelectionArea）
  - Response tab 自动滚动开关（streaming 场景）
- **Feat:** ConfigDetail 增加 bug 图标按钮打开调试面板
- **Refactor:** 移除旧 LogPanel 和 ConfigDetail 实时日志按钮，Debug Inspector Raw Log 完全替代
- **Feat:** 窗口支持自由缩放（最小 800×400）

### v0.2.5
- **Fix:** ConfigDetail not updating when switching configs — added `didUpdateWidget` to re-subscribe SSE and refresh data
- **Feat:** Config list sorts by last used time — `last_used_at` updated on activate and each request, fallback to creation time
- **Feat:** Daemon buildID check on startup — app detects and replaces outdated daemons after upgrade
- **Fix:** VSCode debug `launch.json` PATH includes rvm/CocoaPods

### v0.2.4
- Windows installer support (Inno Setup)
- Windows tray icon and close-to-tray behavior

## Claude Code Rules

- **环境变量同步**：执行需要环境变量的脚本（如 release.sh）之前，必须先 `source ~/.zshrc 2>/dev/null; source ~/.zprofile 2>/dev/null` 以加载用户 shell 配置中的环境变量。不要假设 Claude Code 的 Bash 工具会自动继承用户在终端中设置的变量。

## attendion
每次重要的功能设计变更要更新到项目知识文档中
