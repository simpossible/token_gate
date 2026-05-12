# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Token Gate is a local proxy gateway that manages multiple Claude API keys for AI coding tools (Claude Code, Cursor, etc.). It intercepts requests, injects the active API key and model, records token usage, and exposes a web GUI for management. The final artifact is a single Go binary with the Vue frontend embedded.

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
- Run the script from the **project root** (where `server/` and `web/` live), not from inside `server/`.
- The formula in `homebrew/token_gate.rb` is not the one Homebrew uses — it's a reference copy. The live formula is in the `homebrew-tap` repo (`git@github.com:simpossible/homebrew-tap.git`), updated automatically by the script.
- After release, users install with:
  ```bash
  brew tap simpossible/tap
  brew install token_gate
  ```

## Build Commands

```bash
# Full build (frontend + backend)
cd server && make build          # builds web first, then embeds into Go binary → ./token_gate

# Frontend only
cd web && npm install && npm run build   # outputs to web/dist/

# Backend only (requires web/dist/ to exist)
cd server && go build -o token_gate .

# Run the server (starts all three ports)
./server/token_gate

# Frontend dev server (proxies /api → 127.0.0.1:12122)
cd web && npm run dev            # http://localhost:5173
```

The Makefile copies `web/dist/` into `server/internal/web/dist/` before compiling so Go's `//go:embed dist/*` can pick it up.

## Three-Port Architecture

| Port  | Role              | Handler            |
|-------|-------------------|--------------------|
| 12121 | API proxy         | `internal/proxy`   |
| 12122 | Config REST API   | `internal/api`     |
| 12123 | Web GUI (static)  | `internal/web`     |

All three ports bind to `127.0.0.1` only.

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

## Frontend Architecture

Vue 3 + Composition API, Element Plus, ECharts (raw `echarts/core`, not vue-echarts). No router — page state managed in `App.vue` via `currentPage` ref (`'list' | 'detail' | 'create' | 'edit'`).

`web/src/api/index.js` uses empty `baseURL` in dev mode (goes through Vite's `/api` proxy to port 12122) and `http://127.0.0.1:12122` in production.

Edit switching from `ConfigDetail` → `ConfigForm` uses `window.__openEdit(id)` (a hack to cross component boundaries without a router).

`ConfigDetail.vue` uses raw `echarts.init(domRef)` — the chart instance is created in `renderChart()`, re-initialized on tab change, and disposed in `onUnmounted`.

**Agent type tabs**: `App.vue` renders pill tabs in the header for each registered agent type (`selectedAgentType` ref). Switching tabs calls `getConfigs(agentType)`, filtering the list server-side. The selected agent type is passed down to `ConfigList`, `ConfigForm`, and `ConfigDetail` as a prop.

**Config create flow**: `ConfigForm` shows an `agent_type` selector (required) on create, pre-filled from `selectedAgentType`. On edit the field is read-only (agent type cannot change). `updateConfig` strips `agent_type` from the payload since the backend ignores it on update.

**Activate/deactivate**: Since `agent_type` is stored on the config, the API endpoints `POST /api/configs/:id/activate` and `POST /api/configs/:id/deactivate` no longer require a request body — the backend reads `agent_type` from the config record directly.

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
- **`@updated` propagation**: When `ConfigDetail` emits `updated`, `App.vue` must reload both configs and agents to keep the agent switch state consistent.
- **Web embed requires a build first**: `server/internal/web/dist/` must exist before `go build`. Running `go build` without it will fail due to the `//go:embed dist/*` directive.
- **CORS**: The API server (port 12122) returns `Access-Control-Allow-Origin: *` headers. Port 12123 (web) and port 12122 (API) are different origins so this is required even in production.

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
