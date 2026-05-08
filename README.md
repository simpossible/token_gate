# Token Gate

本地 Claude API 代理网关，为 AI 编程工具（Claude Code、Cursor 等）提供多 
* API Key 管理、
* 一键切换
* ### 用量可视化，可以看到实际的token消耗量，以及时延情况



## 安装

### Homebrew（推荐）

```bash
brew tap simpossible/tap
brew install token_gate
```

### 从源码构建

需要 Go 1.21+ 和 Node.js 18+。

```bash
git clone https://github.com/simpossible/token_gate.git
cd token_gate/server
make build
```

构建产物为 `server/token_gate`，可移到任意 PATH 目录。

## 使用

### 启动与停止

```bash
token_gate start    # 后台启动并打开浏览器
token_gate stop     # 停止后台进程
token_gate show     # 打开 Web 界面（如未运行则自动启动）
token_gate status   # 查看运行状态
```

也可以通过 Homebrew Services 设置开机自启：

```bash
brew services start token_gate
```

启动后，Web 界面默认在 http://127.0.0.1:12123 打开。

### 添加配置

1. 打开 Web 界面，点击 **添加配置**
2. 填写配置名称、API 地址、API Key 和模型
3. API 地址支持预设选择（Anthropic 官方、智谱 AI 等），也可输入自定义地址
4. 保存后配置出现在列表中
<img width="1934" height="660" alt="image" src="https://github.com/user-attachments/assets/3e4e1b01-6d95-44d2-bc1e-50c6de8a5544" />

### 切换配置

在配置列表中点击任意配置进入详情页，通过开关将配置激活到对应的工具。激活后，该工具的所有请求会自动使用此配置的 API Key 和模型。每次切换即时生效，无需重启任何服务。

### 查看用量

在配置详情页中：

- **概览卡片** — 显示总请求数、输入 Token 数、输出 Token 数
- **趋势图表** — 以柱状图展示每日 Token 消耗趋势，可按输入/输出 Token 分别查看

用量数据由代理自动从 SSE 响应中解析，无需额外配置。
<img width="2758" height="1460" alt="image" src="https://github.com/user-attachments/assets/1885563d-a365-4803-907c-3d584ee04bd4" />

<img width="1390" height="530" alt="截屏2026-05-08 15 16 50" src="https://github.com/user-attachments/assets/2dcf0f77-1a82-4c4b-af36-28acda138009" />


## 工作原理

```
AI 编程工具 (Claude Code)
        │
        ▼
  Token Gate 代理 (127.0.0.1:12121)
        │
        ├─ 注入当前激活的 API Key
        ├─ 替换请求中的模型字段
        ├─ 透传 SSE 流式响应
        └─ 异步记录 Token 用量到本地数据库
        │
        ▼
   上游 API (api.anthropic.com)
```

三个本地端口各司其职：

| 端口   | 用途          |
|--------|--------------|
| 12121  | API 代理      |
| 12122  | 配置管理 API  |
| 12123  | Web 管理界面  |

所有端口仅绑定 `127.0.0.1`，数据不离开本机。

## 技术栈

- **后端** — Go，SQLite，HTTP 反向代理
- **前端** — Vue 3 + Element Plus + ECharts
- **构建** — 前端编译后通过 `go:embed` 嵌入 Go 二进制，最终产物为单个可执行文件

## 许可证

MIT
