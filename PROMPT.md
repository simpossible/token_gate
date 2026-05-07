# Token Gate - 多 Agent Token 网关管理工具

## 项目概述

Token Gate 是一个本地代理网关服务，用于管理多个 Claude API Token，为多种 AI 编程工具（Claude Code、Cursor 等）提供统一的代理入口。它将多个 API Key 的管理、按 Agent 切换、使用量统计整合到一个本地服务中，并提供 Web GUI 进行可视化管理。

最终产物是一个 Go 编译的单个二进制可执行文件，内嵌 Web 前端资源，零依赖开箱即用。

---

## 项目结构

```
/Users/tt/dev/open_source/token_gate/
├── PROMPT.md              # 本文件，项目提示词与完整技术方案
├── server/                # Go 后端服务工程
│   ├── go.mod
│   ├── go.sum
│   ├── main.go            # 程序入口
│   └── internal/
│       ├── model/         # 数据模型定义
│       ├── database/      # SQLite 数据库操作
│       ├── proxy/         # API 代理转发（SSE 流式支持）
│       ├── api/           # 配置管理 REST API
│       ├── agent/         # Agent 处理器（抽象接口 + 具体实现）
│       │   ├── processor.go        # AgentProcessor 接口定义
│       │   └── claude_code.go      # Claude Code 处理器实现
│       ├── web/           # 静态文件服务
│       └── config/        # 运行时配置 & 内存缓存
└── web/                   # Vue 前端工程
    ├── package.json
    ├── vite.config.js
    ├── src/
    │   ├── App.vue
    │   ├── main.js
    │   ├── api/            # API 请求封装
    │   ├── views/          # 页面组件
    │   ├── components/     # 通用组件
    │   └── assets/         # 静态资源
    └── dist/               # 构建产物（会被嵌入到 Go 二进制中）
```

---

## 端口规划

| 端口 | 用途 | 说明 |
|------|------|------|
| 12121 | API 代理转发 | 接收 Agent 请求并转发到真实 API |
| 12122 | 配置管理 API | RESTful 接口，管理 Token 配置 |
| 12123 | Web GUI | 静态文件服务，提供管理界面 |

---

## 核心概念

### Agent Type

系统支持多种 AI 编程工具，每种工具称为一种 Agent Type。目前支持：

| Agent Type | 标识 | 说明 |
|------------|------|------|
| Claude Code | `claude_code` | Anthropic 官方 CLI 工具 |
| Cursor | `cursor` | （预留，未来支持） |

同一时间，每个 Agent Type 只有一个生效的 Token 配置。

### 生效配置的运行机制

1. 每个 Agent Type 独立维护"当前生效的配置"
2. 代理端口按 URL 路径中的 `agent_type` 路由到对应配置
3. 切换生效配置时：更新数据库 → 更新内存缓存 → 调用 AgentProcessor 更新本地配置文件

---

## 核心功能

### 1. API 代理转发（端口 12121）

- 监听 `127.0.0.1:12121`，接收请求
- URL 路由规则：`http://127.0.0.1:12121/{agent_type}/...`
  - 例如 Claude Code 请求：`http://127.0.0.1:12121/claude_code/v1/messages`
- 从内存缓存中获取该 `agent_type` 当前生效的 `token_config`
- 替换请求中的 `Authorization: Bearer <api_key>` 头
- 替换请求体中的 `model` 字段为配置中的模型
- 将请求转发到配置的目标 URL（默认 `https://api.anthropic.com`）
- **必须支持 SSE（Server-Sent Events）流式转发**，不能缓冲完整响应后再返回
- 转发过程中记录该次请求的 token 使用量（从响应中提取），带上 `agent_type` 标记
- 透传所有请求头和响应头，保持与原始 API 的完全兼容

### 2. 配置管理 API（端口 12122）

提供 RESTful API 用于管理 Token 配置：

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | /api/configs | 新增配置 |
| DELETE | /api/configs/:id | 删除配置 |
| PUT | /api/configs/:id | 修改配置 |
| GET | /api/configs | 查询配置列表 |
| GET | /api/configs/:id/usage | 获取指定配置的使用量（按 agent_type 分组） |
| POST | /api/configs/:id/activate | 为指定 agent_type 激活此配置 |
| POST | /api/configs/:id/deactivate | 为指定 agent_type 取消激活此配置 |
| GET | /api/agents | 获取所有 agent type 及其当前生效配置 |

### 3. Web GUI 文件服务（端口 12123）

- 从 `$HOME/.token_gate/web/` 目录提供静态文件服务
- 提供 Vue + Element Plus 开发的管理界面

---

## 数据模型

### token_config 表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT | 主键，UUID |
| name | TEXT | 配置显示名称 |
| url | TEXT | API 请求目标地址，如 `https://api.anthropic.com` |
| api_key | TEXT | Anthropic API Key |
| model | TEXT | 默认模型，如 `claude-sonnet-4-6` |
| created_at | DATETIME | 创建时间 |
| updated_at | DATETIME | 更新时间 |

### valid_config 表（生效配置映射）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT | 主键，UUID |
| token_id | TEXT | 外键，关联 token_config.id |
| agent_type | TEXT | Agent 类型标识，如 `claude_code`、`cursor` |
| created_at | DATETIME | 创建时间 |

约束：`agent_type` 唯一，同一时间每个 agent_type 只有一条记录（一个生效配置）。

### usage 表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT | 主键，UUID |
| token_id | TEXT | 外键，关联 token_config.id |
| agent_type | TEXT | 产生此用量的 Agent 类型 |
| input_tokens | INTEGER | 输入 token 数 |
| output_tokens | INTEGER | 输出 token 数 |
| model | TEXT | 本次请求使用的模型 |
| request_path | TEXT | 请求路径 |
| created_at | DATETIME | 记录时间 |

---

## 内存缓存设计

程序启动后，从 `valid_config` 表加载所有生效配置到内存：

```go
// 内存缓存结构
type ActiveConfigCache struct {
    mu      sync.RWMutex
    configs map[string]*TokenConfig  // key = agent_type, value = 对应的 token_config
}
```

- 启动时从数据库加载
- 激活/取消激活配置时同步更新
- 代理转发时从缓存读取，避免每次请求查数据库

---

## Agent 处理器（抽象设计）

### 接口定义

```go
type AgentProcessor interface {
    // GetType 返回 agent_type 标识
    GetType() string
    // OnActivate 当配置被激活时调用，负责更新本地 Agent 配置文件
    OnActivate(config *TokenConfig) error
    // OnDeactivate 当配置被取消激活时调用
    OnDeactivate(config *TokenConfig) error
}
```

### Claude Code 处理器（cc_processor）

`agent_type` 为 `claude_code` 的具体实现：

- **OnActivate**：读取 `$HOME/.claude/settings.json`，将 `ANTHROPIC_BASE_URL` 更新为 `http://127.0.0.1:12121/claude_code`
- **OnDeactivate**：可选操作（目前不需要，因为同一 agent_type 始终有一个生效配置）

当用户在 Web GUI 或 API 中为 `claude_code` 激活一个新配置时：
1. 数据库中删除旧的 `valid_config` 记录，插入新的
2. 更新内存缓存
3. 调用 `cc_processor.OnActivate(newConfig)` 更新 settings.json

### 未来扩展示例（Cursor）

```go
type CursorProcessor struct{}

func (p *CursorProcessor) GetType() string { return "cursor" }
func (p *CursorProcessor) OnActivate(config *TokenConfig) error {
    // 更新 Cursor 的配置文件
    return nil
}
```

只需实现 `AgentProcessor` 接口并注册即可支持新的 Agent。

---

## 程序启动流程

1. **创建数据目录**：检查 `$HOME/.token_gate/` 目录是否存在，不存在则创建
2. **初始化数据库**：在 `$HOME/.token_gate/token_gate.db` 创建 SQLite 数据库，执行建表语句（如已存在则跳过）
3. **解压 Web 资源**：将 Go 二进制中嵌入的 Web 前端资源解压到 `$HOME/.token_gate/web/` 目录
4. **注册 Agent 处理器**：初始化所有支持的 `AgentProcessor` 实现（目前仅 `cc_processor`）
5. **加载内存缓存**：从 `valid_config` 表读取所有生效配置，加载到内存缓存中
6. **扫描已有配置**（仅首次启动，数据库为空时）：
   - 读取 `$HOME/.claude/settings.json`
   - 提取其中的 `ANTHROPIC_AUTH_TOKEN`（或 `ANTHROPIC_API_KEY`）、`ANTHROPIC_BASE_URL`、`model` 信息
   - 如果存在有效配置，自动创建一个名为 `default` 的 `token_config` 记录
   - 并在 `valid_config` 表中为 `claude_code` agent type 创建生效记录
7. **启动三个端口的服务**：
   - 12121：API 代理服务
   - 12122：配置管理 API
   - 12123：Web GUI 文件服务
8. **输出启动信息**：打印三个端口的访问地址

---

## API 代理转发详细设计

### 请求处理流程

```
Claude Code CLI
    │
    │  请求发送到 http://127.0.0.1:12121/claude_code/v1/messages
    │
    ▼
Token Gate 代理服务（:12121）
    │
    ├─ 1. 从 URL 路径提取 agent_type = "claude_code"
    ├─ 2. 从内存缓存获取该 agent_type 当前生效的 token_config
    │     （如果无生效配置，返回 503 错误）
    ├─ 3. 去掉路径中的 agent_type 前缀，还原为真实 API 路径
    │     /claude_code/v1/messages → /v1/messages
    ├─ 4. 替换 Authorization header 为该 config 的 api_key
    ├─ 5. 替换请求体中的 model 字段为该 config 的 model
    ├─ 6. 拼接完整目标 URL: config.url + 真实路径
    ├─ 7. 转发请求到目标 API
    ├─ 8. 检测响应类型：
    │      ├─ SSE 流式响应：逐块转发（flush each chunk）
    │      └─ 普通响应：直接转发
    ├─ 9. 从响应中提取 usage 数据（input_tokens, output_tokens）
    └─ 10. 异步写入 usage 记录到数据库（带上 agent_type）
    │
    ▼
返回给 Claude Code CLI
```

### URL 路由示例

| 代理请求 URL | agent_type | 转发到 |
|-------------|------------|--------|
| `http://127.0.0.1:12121/claude_code/v1/messages` | `claude_code` | `{config.url}/v1/messages` |
| `http://127.0.0.1:12121/cursor/v1/messages` | `cursor` | `{config.url}/v1/messages` |

### SSE 流式转发关键点

- 使用 `Transfer-Encoding: chunked` 逐块转发
- 每个 chunk 收到后立即 flush 到客户端，不缓冲
- 在流式响应中解析 `event: message_delta` 数据块，提取 usage 信息
- 设置合理的超时时间（建议 5 分钟）

### Claude Code 接入方式

当用户为 `claude_code` 激活一个配置时，`cc_processor` 会自动更新 `$HOME/.claude/settings.json`：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:12121/claude_code",
    "ANTHROPIC_API_KEY": "placeholder"
  }
}
```

`ANTHROPIC_API_KEY` 设为任意值即可，实际的 Key 由 Token Gate 代理替换。

---

## 配置管理 API 详细设计

### POST /api/configs — 新增配置

请求体：
```json
{
  "name": "我的 Anthropic 账号",
  "url": "https://api.anthropic.com",
  "api_key": "sk-ant-xxx",
  "model": "claude-sonnet-4-6"
}
```

响应：
```json
{
  "id": "uuid-new",
  "name": "我的 Anthropic 账号",
  "url": "https://api.anthropic.com",
  "api_key": "sk-ant-***xxx",
  "model": "claude-sonnet-4-6"
}
```

### PUT /api/configs/:id — 修改配置

请求体（所有字段可选）：
```json
{
  "name": "新名称",
  "url": "https://new-api.example.com",
  "api_key": "sk-ant-yyy",
  "model": "claude-opus-4-7"
}
```

如果该配置当前在某个 agent_type 中生效，修改后需同步更新内存缓存。

### DELETE /api/configs/:id — 删除配置

- 如果该配置在某个 agent_type 中生效，先取消激活（调用对应 processor 的 OnDeactivate，并删除 valid_config 记录），再删除配置
- 同时删除该配置的所有 usage 记录

### GET /api/configs — 配置列表

响应：
```json
{
  "configs": [
    {
      "id": "uuid-1",
      "name": "default",
      "url": "https://api.anthropic.com",
      "api_key": "sk-ant-***xxx",
      "model": "claude-sonnet-4-6",
      "active_agents": ["claude_code"],
      "created_at": "2026-05-07T10:00:00Z",
      "updated_at": "2026-05-07T10:00:00Z"
    },
    {
      "id": "uuid-2",
      "name": "备用账号",
      "url": "https://api.anthropic.com",
      "api_key": "sk-ant-***yyy",
      "model": "claude-opus-4-7",
      "active_agents": [],
      "created_at": "2026-05-07T12:00:00Z",
      "updated_at": "2026-05-07T12:00:00Z"
    }
  ]
}
```

注意：
- `api_key` 应脱敏显示，仅保留前4位和后4位
- `active_agents` 字段表示该配置在哪些 agent_type 中生效

### GET /api/configs/:id/usage — 使用量（按 agent_type 分组）

响应：
```json
{
  "token_id": "uuid-1",
  "total_input_tokens": 150000,
  "total_output_tokens": 30000,
  "records_count": 42,
  "by_agent": {
    "claude_code": {
      "input_tokens": 150000,
      "output_tokens": 30000,
      "requests": 42
    }
  },
  "daily_usage": [
    {
      "date": "2026-05-07",
      "input_tokens": 50000,
      "output_tokens": 10000,
      "requests": 15,
      "agent_type": "claude_code"
    }
  ]
}
```

### POST /api/configs/:id/activate — 激活配置

请求体：
```json
{
  "agent_type": "claude_code"
}
```

处理流程：
1. 查找该 agent_type 当前的 valid_config 记录，如果存在则删除
2. 插入新的 valid_config 记录（token_id = :id, agent_type）
3. 更新内存缓存
4. 调用对应 AgentProcessor 的 OnActivate 方法

### POST /api/configs/:id/deactivate — 取消激活

请求体：
```json
{
  "agent_type": "claude_code"
}
```

处理流程：
1. 删除该 agent_type 的 valid_config 记录
2. 更新内存缓存（移除该 agent_type 的缓存）
3. 调用对应 AgentProcessor 的 OnDeactivate 方法

### GET /api/agents — 所有 Agent 状态

响应：
```json
{
  "agents": [
    {
      "type": "claude_code",
      "label": "Claude Code",
      "active_config_id": "uuid-1",
      "active_config_name": "default"
    },
    {
      "type": "cursor",
      "label": "Cursor",
      "active_config_id": null,
      "active_config_name": null
    }
  ]
}
```

---

## Web GUI 设计

### 技术栈

- Vue 3（Composition API）
- Element Plus（UI 组件库）
- ECharts（使用量图表）
- Vite（构建工具）
- Axios（HTTP 请求）

### 页面结构

#### 主页面 — 配置列表

- 页面标题：「Token Gate」
- 主体区域为卡片网格布局（响应式，自动换行）
- 每个配置显示为一张长方形卡片，内容包含：
  - 配置名称（加粗大字）
  - API URL
  - 默认模型
  - **生效标签**：显示该配置当前在哪些 Agent 中生效，以 Tag 标签形式展示（如 `Claude Code` 绿色标签，`Cursor` 蓝色标签）。未在任何 Agent 中生效则不显示标签
  - 使用量摘要：累计 input tokens / output tokens（转换为万单位显示）
  - 点击卡片进入该配置的详情页
- 最后一张卡片为「+」加号卡片（虚线边框），点击进入创建配置页面

#### 配置详情页

- **配置信息区域**：
  - 显示配置的完整信息（名称、URL、API Key 脱敏、模型）
  - 「编辑」按钮：修改配置信息
  - 「删除」按钮：删除该配置（需二次确认）

- **Agent 生效管理区域**：
  - 列出所有支持的 Agent Type（目前为 Claude Code，未来会有 Cursor 等）
  - 每个 Agent Type 旁边有一个**开关（Switch）**
  - 打开开关 = 为该 Agent 激活此配置（调用 activate API）
  - 关闭开关 = 为该 Agent 取消激活此配置（调用 deactivate API）
  - 开关状态实时反映当前生效情况

- **使用量图表区域**：
  - 按 Agent Type 分组显示使用量
  - 提供 Tab 切换不同 Agent Type
  - 每个 Tab 下按天展示近 7 天的 input/output tokens 柱状图
  - 显示总请求数、总 token 数

#### 创建/编辑配置页

- 表单字段：
  - 配置名称（必填）
  - API URL（必填，默认 `https://api.anthropic.com`）
  - API Key（必填，密码输入框，可切换显示/隐藏）
  - 默认模型（必填，默认 `claude-sonnet-4-6`）
- 「保存」和「取消」按钮

---

## Go 服务技术选型

| 组件 | 选择 | 说明 |
|------|------|------|
| HTTP 框架 | net/http (标准库) | 轻量，无需第三方依赖 |
| 路由 | go-chi/chi v5 | 轻量 RESTful 路由 |
| 数据库 | modernc.org/sqlite | 纯 Go 实现的 SQLite，无需 CGO |
| UUID | github.com/google/uuid | 生成唯一 ID |
| 前端嵌入 | embed (标准库) | 将 Web 构建产物嵌入二进制 |
| JSON 处理 | encoding/json (标准库) | 序列化/反序列化 |

---

## 构建流程

```bash
# 1. 构建前端
cd web && npm run build    # 产物输出到 web/dist/

# 2. 构建后端（嵌入前端资源）
cd server && make build    # 生成 token_gate 二进制

# 3. 运行
./token_gate              # 启动服务，自动初始化
```

### Makefile 关键目标

```makefile
.PHONY: build clean

build:
	cd ../web && npm install && npm run build
	cp -r ../web/dist/ ./internal/web/dist/
	go build -o token_gate .

clean:
	rm -f token_gate
	rm -rf internal/web/dist/
```

---

## 安全注意事项

1. **API Key 存储**：SQLite 中的 API Key 为明文存储（本地工具，接受此风险），后续可考虑加密
2. **仅监听 localhost**：三个端口均绑定 `127.0.0.1`，不对外暴露
3. **API Key 脱敏**：所有 API 响应和 Web 展示中，API Key 仅显示前4位和后4位
4. **Web GUI 无需认证**：本地工具，仅 localhost 可访问

---

## 开发顺序建议

1. **server/internal/model** — 定义数据结构（token_config、valid_config、usage）
2. **server/internal/agent** — 定义 AgentProcessor 接口 + cc_processor 实现
3. **server/internal/database** — SQLite 初始化、建表、CRUD 操作
4. **server/internal/config** — 内存缓存管理（加载、更新、读取）
5. **server/internal/proxy** — API 代理转发（按 agent_type 路由 + SSE 流式）
6. **server/internal/api** — 配置管理 REST API（含激活/取消激活逻辑）
7. **server/internal/web** — 静态文件服务 + embed 嵌入
8. **server/main.go** — 程序入口，串联启动流程
9. **web/** — Vue 前端开发
10. **Makefile** — 构建脚本整合
