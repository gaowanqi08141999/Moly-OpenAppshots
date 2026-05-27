# QClaw-APPScreenshots — 智能体插件架构设计

> 将 macOS Appshots 能力封装为通用 Agent Tool Use 和 MCP 插件，同时兼容 Hermes Agents 和 OpenClaw 架构。

---

## 一、核心设计决策：MCP-First

**为什么选 MCP 作为统一接口？**

Hermes Agents 和 OpenClaw 都原生支持 MCP（Model Context Protocol），所以最务实的策略是：

```
代码写一次 → MCP Server → 两个框架零代码接入
```

| 框架 | 接入方式 | 额外工作量 |
|------|---------|-----------|
| **Hermes Agents** | MCP 配置 + 可选专用 tool 文件 | ~50 行 Python |
| **OpenClaw** | 纯 `openclaw.json` 配置 | **0 行代码** |

---

## 二、总体分层架构

```
┌──────────────────────────────────────────────────────────────┐
│                     Agent 层（调用方）                         │
│                                                               │
│  ┌─────────────────────┐    ┌──────────────────────────────┐ │
│  │   Hermes Agents      │    │        OpenClaw              │ │
│  │                      │    │                              │ │
│  │  config.yaml:        │    │  openclaw.json:              │ │
│  │   mcp_servers:       │    │   mcp.servers.qclaw-appshot  │ │
│  │     qclaw-appshot    │    │                              │ │
│  │                      │    │  → 自动发现全部 5 个 tool     │ │
│  │  tools/appshot.py    │    │  → 自动注册 4 个 resource    │ │
│  │  (可选增强封装)       │    │                              │ │
│  └──────────┬───────────┘    └──────────────┬───────────────┘ │
│             │                               │                 │
│             │       MCP Protocol            │                 │
│             └───────────────┬───────────────┘                 │
│                             │                                 │
└─────────────────────────────┼─────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                MCP Server 层 (Python, mcp SDK)                │
│                                                               │
│  Tools (Agent 可调用的工具):                                   │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ take_appshot      捕获当前前台窗口的截图 + AX 文本       │ │
│  │ list_appshots     浏览历史快照列表（支持筛选/分页）       │ │
│  │ get_appshot       获取单个快照完整详情                    │ │
│  │ search_appshots   全文搜索快照内容                        │ │
│  │ delete_appshot    删除指定快照                           │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  Resources (Agent 可读取的资源):                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ appshot://{id}/screenshot     快照截图 (PNG)            │ │
│  │ appshot://{id}/accessibility  Accessibility 树 (JSON)   │ │
│  │ appshot://{id}/metadata       元数据 (JSON)             │ │
│  │ appshot://recent              最近一次快照摘要          │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  内部组件:                                                    │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ DaemonClient    通过 Unix Socket 与 Rust 守护进程通信    │ │
│  │ StorageQuery    直接读取 ~/snapshots/ 文件系统元数据    │ │
│  │ ImageProcessor  图片缩放/压缩（发送给 LLM 前处理）      │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
└─────────────────────────────┬─────────────────────────────────┘
                              │ Unix Socket / HTTP localhost
                              ▼
┌──────────────────────────────────────────────────────────────┐
│            Capture Daemon (Rust) — macOS 原生层               │
│                                                               │
│  ┌──────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │ Hotkey       │  │ CaptureEngine    │  │ StorageEngine │  │
│  │ Listener     │  │                  │  │               │  │
│  │              │  │ ScreenCaptureKit │  │ Filesystem    │  │
│  │ CGEvent      │  │ Accessibility    │  │ SQLite Index  │  │
│  │ ⌘⌘ 触发     │  │ 双路并行捕获     │  │ Pruning       │  │
│  └──────┬───────┘  └────────┬─────────┘  └───────┬───────┘  │
│         │                   │                    │          │
│         └───────────────────┴────────────────────┘          │
│                             │                                │
│                    IPC Server                                │
│                  (Unix Socket)                               │
│                    /tmp/qclaw-appshot.sock                   │
│                                                              │
│  POST   /capture          触发捕获                           │
│  GET    /snapshots        列出快照                           │
│  GET    /snapshots/:id    获取快照                           │
│  DELETE /snapshots/:id    删除快照                           │
│  GET    /health           健康检查                           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 三、项目目录结构

```
QClaw-APPScreenshots/
├── PLAN.md                          # 功能规划与概念验证
├── ARCHITECTURE.md                  # 本文档：架构设计
│
├── capture-daemon/                  # Rust 原生捕获守护进程
│   ├── Cargo.toml
│   ├── src/
│   │   ├── main.rs                  # 入口，启动 IPC 服务 + hotkey 监听
│   │   ├── ipc.rs                   # Unix Socket HTTP 服务
│   │   ├── capture.rs              # ScreenCaptureKit + Accessibility API
│   │   ├── storage.rs              # 文件系统 + SQLite
│   │   ├── hotkey.rs               # CGEvent 全局热键
│   │   └── error.rs                # 错误类型
│   └── entitlements/
│       └── capture.entitlements     # macOS 权限声明
│
├── mcp-server/                      # MCP Server (Python)
│   ├── pyproject.toml
│   ├── src/
│   │   └── qclaw_appshots/
│   │       ├── __init__.py
│   │       ├── __main__.py          # python -m qclaw_appshots
│   │       ├── server.py            # MCP Server 主入口
│   │       ├── tools.py             # 5 个 tool 的 schema + handler
│   │       ├── resources.py         # 4 个 resource 定义
│   │       ├── daemon_client.py     # 与 Rust daemon 的 IPC 客户端
│   │       └── image_processor.py   # 图片缩放/压缩
│   └── README.md
│
├── hermes-plugin/                    # Hermes Agents 集成
│   ├── tools/
│   │   └── appshot.py               # Hermes registry.register() 工具
│   ├── config.example.yaml          # Hermes MCP 配置示例
│   └── README.md
│
├── openclaw-plugin/                  # OpenClaw 集成
│   ├── openclaw.json                # 配置示例
│   └── README.md
│
└── examples/                         # 使用示例
    ├── hermes-conversation.md        # Hermes Agent 对话示例
    └── openclaw-conversation.md      # OpenClaw 对话示例
```

---

## 四、MCP Tools 完整定义

### 4.1 take_appshot

```
名称: take_appshot
描述: 捕获当前 macOS 前台窗口的截图和完整的 Accessibility 文本树。
      图片会保存为 PNG 文件，文本会保存为结构化 JSON。
      这是让 AI 理解用户当前屏幕上下文的核心工具。

参数: 无（自动捕获前台窗口）

返回:
{
  "snapshot_id": "2026-05-27_Visual Studio Code_14-32-05",
  "app_name": "Visual Studio Code",
  "bundle_id": "com.microsoft.VSCode",
  "window_title": "app.ts — my-project",
  "timestamp": "2026-05-27T14:32:05+08:00",
  "image_path": "/Users/jane/snapshots/2026-05-27/Visual Studio Code-14-32-05/screenshot.png",
  "image_size": { "width": 3840, "height": 2084 },
  "text_preview": "前 500 字符的文本预览...",
  "text_length": 2847,
  "element_count": 156
}
```

### 4.2 list_appshots

```
名称: list_appshots
描述: 列出历史快照，支持按应用、日期筛选和分页。

参数:
{
  "app_name": "string | null",     // 按应用名筛选
  "date_from": "string | null",    // 起始日期 "2026-05-25"
  "date_to": "string | null",      // 结束日期
  "limit": "int (default 20)",
  "offset": "int (default 0)"
}

返回:
{
  "total": 47,
  "items": [
    {
      "snapshot_id": "...",
      "app_name": "Google Chrome",
      "window_title": "GitHub — openai/codex",
      "timestamp": "2026-05-27T14:32:05+08:00",
      "text_length": 5120
    },
    ...
  ]
}
```

### 4.3 get_appshot

```
名称: get_appshot
描述: 获取单个快照的完整内容，包括 base64 编码的截图和完整的 Accessibility 树。

参数:
{
  "snapshot_id": "string (required)",
  "include_image": "bool (default true)",
  "include_ax_tree": "bool (default true)",
  "image_max_width": "int | null (default 2048)"   // 发送给 LLM 时压缩尺寸
}

返回:
{
  "metadata": { ... },
  "image_base64": "iVBORw0KGgo...",           // 可能被缩放
  "accessibility_tree": { ... 完整 AX 树 },    // 可能被截断
  "full_text": "提取的全部纯文本"               // 扁平化的文本
}
```

### 4.4 search_appshots

```
名称: search_appshots
描述: 在快照元数据和 Accessibility 文本中全文搜索。

参数:
{
  "query": "string (required)",    // 搜索词
  "search_in": "string (default 'all')"  // "all" | "window_title" | "text" | "app_name"
}

返回:
{
  "query": "error",
  "results": [
    {
      "snapshot_id": "...",
      "app_name": "Terminal",
      "matched_in": "text",
      "snippet": "...包含搜索词的上下文片段..."
    }
  ]
}
```

### 4.5 delete_appshot

```
名称: delete_appshot
描述: 删除指定快照及其所有文件。

参数:
{
  "snapshot_id": "string (required)"
}

返回:
{
  "success": true,
  "deleted_files": ["screenshot.png", "metadata.json", "accessibility_tree.json"]
}
```

---

## 五、MCP Resources 定义

| URI Pattern | 描述 | MIME Type |
|---|---|---|
| `appshot://recent` | 最近一次快照的元数据摘要 | `application/json` |
| `appshot://{id}/screenshot` | 快照的 PNG 截图 | `image/png` |
| `appshot://{id}/accessibility` | 完整的 Accessibility Tree | `application/json` |
| `appshot://{id}/metadata` | 快照元数据 | `application/json` |

---

## 六、Hermes Agents 集成方案

### 方案一（推荐）：MCP 配置驱动

Hermes 原生支持通过配置文件接入外部 MCP Server：

```yaml
# hermes config.yaml
mcp_servers:
  - name: qclaw-appshot
    transport: stdio
    command: python
    args: ["-m", "qclaw_appshots"]
    env:
      QCLAW_DAEMON_SOCK: "/tmp/qclaw-appshot.sock"
      QCLAW_SNAPSHOT_DIR: "~/snapshots"
```

配置后 Hermes 会自动发现 5 个 tool + 4 个 resource，无需写代码。

### 方案二（增强）：专用 Tool 文件 + MCP 混合

提供 `tools/appshot.py`，在 Hermes 工具系统中注册，同时作为 MCP 客户端的薄封装。优势：

- `check_fn` 做 macOS 可用性检查，不满足时工具不出现
- 可以注册到 `appshot` 自定义 toolset
- 可以增加 Hermes 特有的日志、错误处理

```python
# hermes-plugin/tools/appshot.py
import asyncio
import json
from tools.registry import registry

MCP_SERVER_COMMAND = ["python", "-m", "qclaw_appshots"]


def _check_macos_daemon():
    """检查是否为 macOS 且 daemon socket 可用"""
    import platform
    import os
    if platform.system() != "Darwin":
        return False
    return os.path.exists("/tmp/qclaw-appshot.sock")


async def take_appshot(**kwargs) -> str:
    """调用 MCP Server 的 take_appshot 工具"""
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client

    server_params = StdioServerParameters(
        command=MCP_SERVER_COMMAND[0],
        args=MCP_SERVER_COMMAND[1:]
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool("take_appshot", {})
            return json.dumps(result.content[0].text, ensure_ascii=False)


async def list_appshots(args: dict, **kwargs) -> str:
    """调用 MCP Server 的 list_appshots 工具"""
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client

    server_params = StdioServerParameters(
        command=MCP_SERVER_COMMAND[0],
        args=MCP_SERVER_COMMAND[1:]
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool("list_appshots", args)
            return json.dumps(result.content[0].text, ensure_ascii=False)


# ========== 注册到 Hermes 工具系统 ==========

registry.register(
    name="take_appshot",
    toolset="appshot",
    schema={
        "name": "take_appshot",
        "description": "捕获当前 macOS 前台窗口的截图和完整的 Accessibility 文本树。"
                       "捕获内容包括: (1) 高保真 PNG 截图 (2) 应用内所有 UI 元素的"
                       "结构化文本（包括屏幕外不可见内容）。适用于让 AI 理解用户当前"
                       "正在查看的应用窗口。",
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    handler=lambda args, **kw: asyncio.run(take_appshot()),
    check_fn=_check_macos_daemon,
    is_async=True,
    emoji="📸",
    description="捕获前台窗口的截图和 Accessibility 文本",
)

registry.register(
    name="list_appshots",
    toolset="appshot",
    schema={
        "name": "list_appshots",
        "description": "列出所有历史快照。可按应用名称、日期范围筛选，支持分页。",
        "parameters": {
            "type": "object",
            "properties": {
                "app_name": {"type": "string", "description": "按应用名筛选"},
                "date_from": {"type": "string", "description": "起始日期 YYYY-MM-DD"},
                "date_to": {"type": "string", "description": "结束日期 YYYY-MM-DD"},
                "limit": {"type": "integer", "description": "返回数量，默认 20"},
                "offset": {"type": "integer", "description": "偏移量，默认 0"}
            }
        }
    },
    handler=lambda args, **kw: asyncio.run(list_appshots(args)),
    check_fn=_check_macos_daemon,
    is_async=True,
    emoji="📋",
    description="浏览历史快照列表",
)

# get_appshot, search_appshots, delete_appshot 同理注册...
```

### Hermes Plugin 目录结构

```
hermes-plugin/
├── tools/
│   ├── __init__.py
│   └── appshot.py              # 上述注册代码
├── skills/
│   └── appshot-context.md      # Hermes Skill，教 Agent 何时使用截图
└── config.example.yaml
```

---

## 七、OpenClaw 集成方案

OpenClaw 只需 JSON 配置，零代码：

### openclaw.json

```json
{
  "mcp": {
    "servers": {
      "qclaw-appshot": {
        "command": "python",
        "args": ["-m", "qclaw_appshots"],
        "transport": "stdio",
        "env": {
          "QCLAW_DAEMON_SOCK": "/tmp/qclaw-appshot.sock",
          "QCLAW_SNAPSHOT_DIR": "/Users/jane/snapshots"
        }
      }
    }
  },
  "tools": {
    "sandbox": {
      "tools": {
        "allow": ["qclaw-appshot_take_appshot", "qclaw-appshot_list_appshots", "qclaw-appshot_get_appshot", "qclaw-appshot_search_appshots", "qclaw-appshot_delete_appshot"]
      }
    }
  }
}
```

### 如果使用 openclaw-mcp-adapter 插件路径：

```json
{
  "plugins": {
    "entries": {
      "mcp-adapter": {
        "enabled": true,
        "config": {
          "servers": [
            {
              "name": "qclaw-appshot",
              "transport": "stdio",
              "command": "python",
              "args": ["-m", "qclaw_appshots"],
              "env": {
                "QCLAW_DAEMON_SOCK": "/tmp/qclaw-appshot.sock"
              }
            }
          ]
        }
      }
    }
  }
}
```

---

## 八、Capture Daemon (Rust) 接口规范

### IPC 协议

Daemon 在 `/tmp/qclaw-appshot.sock` 上提供 HTTP/1.1 服务：

| Method | Path | Request Body | Response | 说明 |
|--------|------|-------------|----------|------|
| `POST` | `/capture` | 无 | `SnapshotSummary` JSON | 触发捕获 |
| `GET` | `/snapshots` | Query: `?app=&from=&to=&limit=&offset=` | `SnapshotList` JSON | 列出快照 |
| `GET` | `/snapshots/:id` | 无 | `SnapshotFull` JSON | 获取详情 |
| `DELETE` | `/snapshots/:id` | 无 | `{success: bool}` | 删除 |
| `GET` | `/screenshots/:id` | Query: `?max_width=` | PNG binary | 获取截图 |
| `GET` | `/health` | 无 | `{status: "ok", uptime: N}` | 健康检查 |

### Hotkey 行为

- 监听 `⌘⌘`（双击左右 Command 键）
- 检测到快捷键 → 自动调用内部 capture → 保存 → 通过回调通知 MCP Server（可选）
- Hotkey 触发和 API 触发走同一套捕获逻辑

---

## 九、数据流全景

```
┌──────────────────────────────────────────────────────────┐
│  场景 1: Agent 主动调用                                   │
│                                                          │
│  User: "帮我看看浏览器里那个报错是什么原因"                │
│                                                          │
│  Agent Loop:                                             │
│  1. LLM 决定调用 take_appshot()                          │
│  2. MCP Server 收到调用                                   │
│     → DaemonClient.send("/capture")                      │
│     → Rust Daemon:                                       │
│       a. CGWindowList 获取前台窗口                       │
│       b. 并行: SCStream 截图 + AXUIElement 遍历          │
│       c. 保存到 ~/snapshots/2026-05-27/Chrome-14:32:05/ │
│       d. 返回 SnapshotSummary                            │
│  3. Agent 看到 app_name="Chrome", text_preview="...Error"│
│  4. LLM 决定调用 get_appshot(id, include_image=true)     │
│  5. MCP Server 返回 base64 截图 + 完整 AX 文本           │
│  6. LLM 分析: "这个错误是 CORS 跨域问题..."              │
│  7. Agent 回复用户                                        │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  场景 2: 用户快捷键触发                                   │
│                                                          │
│  User: ⌘⌘ (双击 Command)                                 │
│                                                          │
│  1. Rust Daemon hotkey listener 捕获事件                  │
│  2. 执行 capture → 保存到文件系统                         │
│  3. Daemon 通过 Unix Socket 推送事件给 MCP Server        │
│  4. MCP Server 通知已连接的 Agent (可选)                  │
│  5. 用户: "分析刚才的截图"                                │
│  6. Agent 调用 get_appshot("recent")                     │
│  7. 拿到最近一次快照内容，继续对话                        │
└──────────────────────────────────────────────────────────┘
```

---

## 十、跨框架对比总结

| 组件 | Hermes Agents | OpenClaw |
|------|--------------|----------|
| **配置方式** | `config.yaml` 的 `mcp_servers` | `openclaw.json` 的 `mcp.servers` |
| **工具发现** | MCP 自动发现 + AST 扫描 `tools/` | MCP 自动发现 |
| **可选增强** | `tools/appshot.py` 专用注册 | 不需要（纯 JSON） |
| **可用性检查** | `check_fn=_check_macos_daemon` | MCP 连接健康检查 |
| **工具分组** | `toolset: "appshot"` | 按 MCP server 名自动分组 |
| **Skills** | `skills/appshot-context.md` | Skills 目录 |
| **权限控制** | toolset 白/黑名单 | `tools.sandbox.tools.allow` |

---

## 十一、关键设计要点

### 1. 为什么 capture daemon 用 Rust 而不是 Python？

- ScreenCaptureKit 和 Accessibility API 是 macOS 原生 C API，Rust 通过 FFI 或 bindings 调用最高效
- Daemon 需要常驻后台，Rust 内存安全且资源占用极低（< 50MB 常驻内存）
- 冷启动 < 200ms，热键响应无延迟

### 2. 为什么 MCP Server 用 Python 而不是全部 Rust？

- Python MCP SDK (`mcp`) 是最成熟的 MCP 实现
- Hermes 本身就是 Python 生态，Python MCP Server 集成最自然
- 工具 schema、错误处理等逻辑在 Python 侧更易迭代
- 性能瓶颈在捕获（Rust）和 LLM 推理（服务端），MCP Server 不是瓶颈

### 3. MCP Server 和 Daemon 为什么分离？

- **进程隔离**：Daemon 需要 macOS 特殊权限（Screen Recording + Accessibility），MCP Server 不需要
- **独立升级**：Daemon 升级不需要重启 MCP Server
- **故障容错**：Daemon 挂了 MCP Server 仍然可以返回缓存/历史数据
- **多客户端**：多个 Agent 框架可以共享同一个 Daemon 进程

### 4. 文本量控制策略

Accessibility Tree 可能非常大（VS Code 3000+ 节点）。MCP Server 需要做截断：

```
take_appshot   → 返回 text_preview (前 500 字符)
get_appshot    → 返回完整 (但可配置 max_elements)
发送给 LLM     → ImageProcessor 压缩图片至 ≤ 2048px 宽
```
