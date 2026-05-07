# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Token Gate is a local proxy gateway that manages multiple Claude API keys for AI coding tools (Claude Code, Cursor, etc.). It intercepts requests, injects the active API key and model, records token usage, and exposes a web GUI for management. The final artifact is a single Go binary with the Vue frontend embedded.

## Release Process

Releasing a new version is a single command:

```bash
# Prerequisite (one-time): authenticate GitHub CLI
gh auth login -h github.com

# Release (run from project root)
./scripts/release.sh v0.1.2
```

The script does everything in order:
1. Cross-compiles for `darwin/arm64` and `darwin/amd64`
2. Packages into `.tar.gz` files in `server/`
3. Tags the commit and pushes tag + master to GitHub
4. Creates a GitHub Release and uploads both tarballs
5. Clones `simpossible/homebrew-tap`, regenerates the formula with updated version and SHA256s, and pushes

**Common pitfalls:**
- `gh auth login` must be done before running the script — `git push` works via SSH but creating a GitHub Release requires the `gh` OAuth token.
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

When a config is activated for an agent type, the flow is:
1. DB: delete old `valid_config` row for that `agent_type`, insert new one
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

SQLite at `~/.token_gate/token_gate.db`. Three tables:
- `token_config` — stored API keys and model per named config
- `valid_config` — one row per `agent_type` (UNIQUE constraint), maps agent → active token
- `usage` — append-only request log with token counts

`api_key` is stored in plaintext (local tool, acceptable risk). All API responses mask it to `first4***last4`.

## Frontend Architecture

Vue 3 + Composition API, Element Plus, ECharts (raw `echarts/core`, not vue-echarts). No router — page state managed in `App.vue` via `currentPage` ref (`'list' | 'detail' | 'create' | 'edit'`).

`web/src/api/index.js` uses empty `baseURL` in dev mode (goes through Vite's `/api` proxy to port 12122) and `http://127.0.0.1:12122` in production.

Edit switching from `ConfigDetail` → `ConfigForm` uses `window.__openEdit(id)` (a hack to cross component boundaries without a router).

`ConfigDetail.vue` uses raw `echarts.init(domRef)` — the chart instance is created in `renderChart()`, re-initialized on tab change, and disposed in `onUnmounted`.

The `GET /api/configs/:id` endpoint returns a bare `TokenConfig` (no `active_agents`). Active agent state in the detail view is derived from the `agents` prop passed down from `App.vue`, not from the config object.

## Key Gotchas

- **`GET /api/configs` vs `GET /api/configs/:id`**: The list endpoint returns `ConfigWithAgents` (includes `active_agents`); the single-item endpoint returns only `TokenConfig`. Don't expect `active_agents` on a single-config fetch.
- **`@updated` propagation**: When `ConfigDetail` emits `updated`, `App.vue` must reload both configs and agents to keep the agent switch state consistent.
- **Web embed requires a build first**: `server/internal/web/dist/` must exist before `go build`. Running `go build` without it will fail due to the `//go:embed dist/*` directive.
- **CORS**: The API server (port 12122) returns `Access-Control-Allow-Origin: *` headers. Port 12123 (web) and port 12122 (API) are different origins so this is required even in production.
