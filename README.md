# Token Gate

**[中文文档](README_CN.md)**

A local Claude API proxy gateway for AI coding tools (Claude Code, Cursor, etc.), providing:

- **Multiple API key management** — store keys from Anthropic, GLM, DeepSeek, Kimi, and more
- **Live switching** — swap vendor or model mid-session; the change takes effect on the very next request, **no need to start a new session**
- **Token usage visualization** — see real input/output token counts and latency per config

<img width="1934" height="660" alt="Config list" src="https://github.com/user-attachments/assets/3e4e1b01-6d95-44d2-bc1e-50c6de8a5544" />

## Installation

### Homebrew (recommended)

```bash
brew tap simpossible/tap
brew install token_gate
```

### Build from source

Requires Go 1.21+ and Node.js 18+.

```bash
git clone https://github.com/simpossible/token_gate.git
cd token_gate/server
make build
```

The binary is output to `server/token_gate` and can be moved anywhere in your `PATH`.

## Usage

### Start / Stop

```bash
token_gate start    # start in background and open browser
token_gate stop     # stop background process
token_gate show     # open Web UI (starts automatically if not running)
token_gate status   # show running status
```

You can also set it to start on login via Homebrew Services:

```bash
brew services start token_gate
```

The Web UI is available at http://127.0.0.1:12123 after startup.

### Add a config

1. Open the Web UI and click **Add Config**
2. Fill in a name, API URL, API Key, and model
3. The API URL field offers presets (Anthropic, GLM, DeepSeek, Kimi, …) or accepts any custom URL
4. Save — the config appears in the list

### Switch configs

Open any config's detail page and toggle it on for the target tool. The change is applied instantly to the in-memory cache; the very next request from Claude Code (or any other tool) will use the new API key and model — **no need to start a new session**.

### View usage

On the config detail page:

- **Summary cards** — total requests, input tokens, output tokens
- **Trend chart** — daily token consumption bar chart, toggleable by input/output

Usage data is parsed automatically from SSE responses; no extra configuration required.

<img width="2758" height="1460" alt="Usage chart" src="https://github.com/user-attachments/assets/1885563d-a365-4803-907c-3d584ee04bd4" />

<img width="1390" height="530" alt="Detail view" src="https://github.com/user-attachments/assets/2dcf0f77-1a82-4c4b-af36-28acda138009" />

## How it works

```
AI coding tool (Claude Code)
        │
        ▼
  Token Gate proxy (127.0.0.1:12121)
        │
        ├─ inject active API key
        ├─ replace model field in request body
        ├─ stream SSE response back transparently
        └─ parse and record token usage asynchronously
        │
        ▼
   Upstream API (api.anthropic.com / any vendor)
```

Three local ports, each with a single responsibility:

| Port  | Role                  |
|-------|-----------------------|
| 12121 | API proxy             |
| 12122 | Config management API |
| 12123 | Web UI                |

All ports bind to `127.0.0.1` only. No data leaves your machine.

## Tech stack

- **Backend** — Go, SQLite, HTTP reverse proxy
- **Frontend** — Vue 3 + Element Plus + ECharts
- **Distribution** — frontend compiled and embedded into the Go binary via `go:embed`; ships as a single executable

## License

MIT
