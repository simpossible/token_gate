# Token Gate Flutter Desktop App — 开发计划

## 背景

### 项目现状

Token Gate 是一个本地代理网关，管理多个 Claude API Key，供 Claude Code / Cursor 等 AI 编程工具使用。核心能力：拦截请求、注入 API Key 和模型、记录 token 用量、提供 Web GUI 管理界面。

**当前技术栈：**
- Go 二进制（daemon 模式独立运行）
  - Port 12121：API 代理（Claude Code 连这里）
  - Port 12122：REST API（管理用）
  - Port 12123：Web GUI（静态 Vue 页面）
- Vue 3 前端（打包后 embed 进 Go 二进制）
- SQLite 数据库（`~/.token_gate/token_gate.db`）
- 发布方式：Homebrew

**第一阶段已完成**：代理、多 Key 管理、token 统计、延迟监控、多 Agent 类型支持等核心能力全部跑通。

### 第二阶段目标

将 Web GUI 升级为原生桌面应用，提升使用体验：
- 应用化的界面（非网页感）
- macOS 状态栏实时显示 token 消耗
- 将 Go 二进制打包进 Flutter 应用分发

---

## 架构设计

### 核心关系（重要）

```
以前：  [Go daemon] 内嵌 web/dist/ → 提供 Web UI（Port 12123）
现在：  [Flutter App] 内嵌 token_gate 二进制
               ↓ 检测未运行时，释放二进制到 ~/.token_gate/ 并启动 daemon
         [Go daemon] 独立运行，与 Flutter 无父子关系
               ↑
         Flutter 通过 HTTP :12122 通信（与原 Web 完全相同）
```

**关键原则：**
- Go daemon 生命周期完全独立，关闭 Flutter 窗口 Go 继续运行
- Flutter 启动只做一件事：检测 `:12122` 是否在线，不在线就启动内嵌二进制
- Go 的 daemon/PID 文件机制（`server/daemon_unix.go` 已有）原封不动复用
- Flutter 关闭窗口 = 最小化到状态栏，proxy 12121 持续服务 Claude Code
- Port 12123（Web GUI）后续可保留供浏览器备用，也可移除

### 目录结构

```
token_gate/
├── server/          (Go 后端，不动)
├── web/             (Vue 前端，保留)
└── app/             (新建 Flutter 桌面应用)
    ├── lib/
    │   ├── main.dart
    │   ├── models/
    │   ├── services/
    │   │   ├── api_service.dart       # 封装所有 :12122 REST 调用
    │   │   ├── backend_service.dart   # 检测/启动 Go daemon
    │   │   └── tray_service.dart      # 状态栏管理
    │   ├── views/
    │   │   ├── home_view.dart
    │   │   ├── config_list.dart
    │   │   ├── config_detail.dart
    │   │   └── config_form.dart
    │   └── widgets/
    ├── macos/
    ├── assets/
    │   └── bin/
    │       └── token_gate             # 编译好的 Go 二进制（构建时注入）
    └── pubspec.yaml
```

---

## UI 设计

### 整体布局（1000 × 600 pt，固定尺寸）

```
┌─────────────────────────────────────────────────────────────────┐
│  区域一（顶部栏）                                                  │
│  TokenGate    [claude_code ▾]                              [+]  │
├──────────┬──────────────────────────────────────────────────────┤
│  区域2.1 │  区域2.2                                              │
│  配置列表 │                                                       │
│  (220pt) │  2.2.1  基本信息                                      │
│          │  2.2.2  统计数字横排                                   │
│  [卡片]  │  2.2.3  Token 折线/柱状图                              │
│  [卡片]  │  2.2.4  延迟折线图                                     │
│  [卡片]  │                                                       │
└──────────┴──────────────────────────────────────────────────────┘
```

### 区域一（顶部栏）
- 左：**TokenGate** 文字 Logo
- 中：当前 Agent 下拉选择（调 `GET /api/agents`，默认 `claude_code`）
- 右：`+` 按钮（创建配置）

### 区域 2.1（配置卡片列表，约 220pt 宽）
- 每张卡片显示：名字、厂商（无匹配时显示 URL）、模型
- 卡片有两个并行独立状态：
  - **选中**（单击）：高亮边框
  - **生效中**（双击 activate）：置顶 + 特殊标识
- 双击已生效的卡片 → deactivate
- 切换 Agent 时刷新列表

### 区域 2.2（详情面板）
无配置时：隐藏 2.2，中央显示大"创建配置"按钮。
有配置且已选中时显示：

**2.2.1 基本信息行**
- ID、Name、Agent Type、厂商/URL、API Key（脱敏）、Model、Created

**2.2.2 统计数字横排**
- Requests、Input Tokens、Output Tokens、Avg Latency
- 数据来源：`GET /api/configs/:id/usage`

**2.2.3 Token 使用图表**
- 折线图（默认），可切换柱状图
- 三条线：Input / Output / Total
- 数据来源：`GET /api/usages` + `GET /api/usage_delta`

**2.2.4 延迟图表**
- 折线图，显示近期请求延迟
- 数据来源：`GET /api/latency/latest`

---

## 分阶段实施计划

### Phase 1 — 项目骨架

**目标：** Flutter 项目能跑起来，主布局可见

- [ ] 在 `app/` 创建 Flutter 项目（`flutter create --platforms=macos,windows,linux app`）
- [ ] 配置 `pubspec.yaml`，引入所有依赖
- [ ] `window_manager`：固定窗口 1000×600，禁止 resize，标题栏自定义
- [ ] 主布局 Scaffold：区域一（顶部）+ 区域二（左右分栏）
- [ ] 关闭窗口 → 窗口隐藏（最小化到状态栏，不 quit）

**依赖：**
```yaml
tray_manager: ^0.2.3
window_manager: ^0.4.3
http: ^1.2.0
fl_chart: ^0.70.0
flutter_riverpod: ^2.6.1
```

---

### Phase 2 — 后端集成

**目标：** Flutter 能启动和连接 Go daemon

- [ ] `BackendService.checkRunning()`：`GET http://127.0.0.1:12122/api/agents` 返回 200 即在线
- [ ] `BackendService.start()`：将 `assets/bin/token_gate` 释放到 `~/.token_gate/token_gate`，赋予执行权限，启动（Go 自身 daemonize）
- [ ] 应用启动流程：check → 未运行则 start → 等待就绪（最多 5s，轮询）→ 进入主界面
- [ ] `ApiService`：封装所有现有 REST endpoint，统一错误处理
- [ ] 构建脚本：`make app` = 先 `go build` 产出对应平台二进制 → 复制到 `app/assets/bin/` → `flutter build macos`

**注意：** Go 的 PID 文件在 `~/.token_gate/token_gate.pid`，`BackendService` 不需要自己维护进程，Go 自己管。

---

### Phase 3 — 核心 UI

**目标：** 完整的配置管理界面

- [ ] 区域一：Agent 下拉（`listAgents`），`+` 按钮打开创建 Sheet
- [ ] 区域 2.1：卡片列表，支持单击选中 / 双击 activate/deactivate，生效卡片置顶
- [ ] 区域 2.2：详情面板骨架 + 2.2.1 基本信息展示
- [ ] 无配置空状态：大"创建配置"按钮居中
- [ ] 创建/编辑表单（名字、API Key、模型、厂商选择）
- [ ] 删除确认弹窗

---

### Phase 4 — 数据与图表

**目标：** 统计和图表可用

- [ ] 2.2.2 统计数字：轮询 `GET /api/configs/:id/usage`
- [ ] 2.2.3 Token 图表：`fl_chart` LineChart / BarChart，折线/柱状切换按钮
- [ ] 2.2.4 延迟图表：`fl_chart` LineChart
- [ ] 切换配置时刷新图表数据

---

### Phase 5 — 状态栏

**目标：** macOS 顶部状态栏实时 token 显示

- [ ] `tray_manager` 初始化，设置图标
- [ ] `tray_manager.setTitle()` 显示实时数据，格式：`↑1.2K ↓856`（单位：上行/下行 token）
- [ ] 定时器每 5s 调 `GET /api/usage_delta` 拿最近增量刷新
- [ ] 下拉菜单：「打开 TokenGate」/ 「停止服务」/ 「退出」
- [ ] 「停止服务」= 调 stop API 或 kill PID 文件里的 PID

---

### Phase 6 — 构建与发布

**目标：** 一条命令完成打包

- [ ] 更新 `scripts/release.sh`：加入 `flutter build macos` 步骤
- [ ] `Makefile` 增加 `make app` target
- [ ] macOS `.app` bundle 包含正确的 entitlements（网络访问、本地文件写入）
- [ ] 产出 `.dmg` 用于直接分发（非 App Store）

---

## 现有 API 接口速查

所有接口在 `http://127.0.0.1:12122`：

| Method | Path | 用途 |
|--------|------|------|
| GET | `/api/agents` | 列出所有 Agent 类型 |
| GET | `/api/configs?agent_type=xxx` | 按 Agent 过滤配置列表 |
| GET | `/api/configs/:id` | 获取单个配置 |
| POST | `/api/configs` | 创建配置 |
| PUT | `/api/configs/:id` | 更新配置 |
| DELETE | `/api/configs/:id` | 删除配置 |
| POST | `/api/configs/:id/activate` | 激活配置 |
| POST | `/api/configs/:id/deactivate` | 停用配置 |
| GET | `/api/configs/:id/usage` | 获取用量统计 |
| GET | `/api/usages` | 获取历史 token 用量列表 |
| GET | `/api/usage_delta` | 获取增量 token 数据（状态栏用） |
| GET | `/api/latency/latest` | 获取最近延迟数据 |
| GET | `/api/companies` | 获取厂商预设列表 |

---

## 工作量估算

| 阶段 | 预估时间 |
|------|---------|
| Phase 1 骨架 | 1 天 |
| Phase 2 后端集成 | 1 天 |
| Phase 3 核心 UI | 2-3 天 |
| Phase 4 图表 | 1-2 天 |
| Phase 5 状态栏 | 0.5 天 |
| Phase 6 构建 | 0.5 天 |
| **合计** | **6-8 天** |

---

## 技术决策记录

1. **框架选 Flutter 而非 Wails**：状态栏实时文字（`tray_manager.setTitle()`）是原生一等公民；新 UI 反正要重写，Dart 学习成本低；自绘引擎 UI 更有应用感。
2. **Go 是独立 daemon，不是子进程**：与 Flutter 无父子依赖，关闭 UI 不影响代理服务，复用现有 PID/daemon 机制。
3. **不改后端任何代码**：Flutter 通过现有 REST API 与 Go 通信，和原 Web 前端完全等价。
4. **不上 App Store**：沙盒限制会阻断写 `~/.claude/settings.json` 和绑定固定端口，走 DMG 直接分发。
5. **窗口关闭 = 最小化到状态栏**：代理服务需常驻，状态栏图标是唯一入口。
