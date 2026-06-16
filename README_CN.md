<img src="https://raw.githubusercontent.com/gaowanqi08141999/Moly-OpenAppshots/main/cover.png" style="display:none">

# Moly — 面向Agent的截图信息挖掘工具

[English](README.md) | [中文](README_CN.md)

> *嘿，人！快把你的屏幕给我看一眼🐱*

**Moly** 一键捕获 macOS 屏幕——截图 + 可访问性文本树——通过标准 MCP 协议喂给任何 AI 智能体。

### Moly 做什么

- **一键截图（⌃⌥⌘Space）**：同时捕获前台窗口的两层信息
- **视觉层**：Retina 2x PNG 高清截图，通过 macOS ScreenCaptureKit 获取
- **文本层**：完整的可访问性元素树——智能体可以读取屏幕上的每一个标签、按钮和段落
- **剪贴板自动复制**：截图自动入剪贴板，⌘V 直接粘贴
- **智能体快路径**：每次截图自动写入 `~/.moly/latest.txt`——智能体只需 `cat` 这个文件就能拿到最新截图目录，零 HTTP 调用

### 实现原理

1. 一个轻量级 Swift daemon（`~/.moly/bin/molyd`）在本地 19876 端口运行
2. 通过 CGEvent tap 全局监听 ⌃⌥⌘Space 快捷键
3. 截图时获取前台窗口 PID，ScreenCaptureKit 截图，同时遍历窗口的可访问性元素树
4. 两者保存到 `~/snapshots/<日期>/<ID>/`，由 SQLite 索引
5. `~/.moly/latest.txt` 原子更新为最新快照目录路径——这是智能体的首选查找路径（一次 `cat`，零 API 调用）
6. PNG 同时嵌入 `moly_path` 元数据作为备用查找路径，然后复制到剪贴板
7. Python MCP 服务器（`moly_mcp.py`）通过 stdio JSON-RPC 暴露 6 个工具——任何 MCP 兼容的智能体都能调用，作为降级备用
8. 浏览器截图时，daemon 还会连接 Chrome DevTools Protocol（CDP）提取完整 DOM 和 CSS——无需手动开启任何浏览器设置

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![MCP](https://img.shields.io/badge/MCP-compatible-purple)](https://modelcontextprotocol.io/)

## 工作原理

```
按下快捷键 ⌃⌥⌘Space
        │
        ▼
┌──────────────────┐
│  ScreenCaptureKit │  →  Retina 2x PNG 截图
│  Accessibility API│  →  结构化文本树 (AX)
│  Chrome CDP (9222)│  →  DOM + CSS (dom.html, styles.json)
└────────┬─────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
 ~/snapshots/   剪贴板（PNG 含嵌入式元数据）
    │              │
    ▼              ▼
  MCP 服务器    智能体解析
  (6 个工具)    元数据直达本地文件
    │              │
    └──────┬───────┘
           ▼
     智能体分析一切
```

**快捷键唤起截图工具，自动获取页面相关的全量AXTree文本树信息**

## 特性

- **⌃⌥⌘Space 快捷键** — daemon 内置，无需 Shortcuts.app
- **双重捕获** — Retina PNG 截图 + 完整 AX 文本树，一次完成
- **剪贴板自动复制** — 截图后直接 ⌘V 粘贴到任意对话框
- **智能体快路径** — `~/.moly/latest.txt` 让智能体一次 `cat` 即获截图路径，零 API 调用
- **网页捕获层** — 自动提取 `page_url.txt`、`dom.html`（完整 DOM）、`styles.json`（CSS/配色/字体/布局），网站复刻利器
- **Electron 应用支持** — `--setup` 自动配置 Electron 桌面应用
- **PNG 元数据嵌入** — 备用查找：PNG `tEXt` 块携带 `moly_path`（图片未被重编码时有效）
- **统一 MCP** — 一套工具 6 个接口，适配 Hermes、OpenClaw、Claude Desktop、Cursor 及任何 MCP 客户端
- **Apple 风格通知** — 右上角白色圆角弹窗，带自定义图标
- **屏幕闪白** — 截图瞬间的视觉反馈
- **100% 本地** — 不上传云端，不需要 API key，不需要网络

## 快速开始

```bash
# 1. 下载安装
git clone https://github.com/gaowanqi08141999/Moly-OpenAppshots.git
cd moly/moly-share
chmod +x install.sh && ./install.sh

# 2. 运行一次性权限设置向导
~/.moly/bin/molyd --setup
#    → 自动配置全部权限，无需手动点系统设置
#    → 涵盖：辅助功能 (molyd)、屏幕录制 (molyd)、
#            辅助功能 (Google Chrome)、辅助功能 (Electron 应用)

# 3. 重启 Chrome（加入 CDP 参数以启用网页捕获）：
#    open -a "Google Chrome" --args \
#        --force-renderer-accessibility \
#        --remote-debugging-port=9222 \
#        --remote-allow-origins=*
#    （Electron 应用仅需：open -a "应用名" --args --force-renderer-accessibility）

# 4. 重启 daemon（授权后必须重启）
killall molyd; sleep 1; ~/.moly/bin/molyd &

# 5. 验证
cd ../capture-daemon && make doctor
# → ✅ Daemon 运行中 / ✅ AX 已授权 / ✅ 截图正常

# 6. 配置智能体的 MCP 服务器（一次性，见下文）

# 7. 准备就绪！在任意窗口按 ⌃⌥⌘Space，粘贴 (⌘V) 给 Agent

# 💡 每次重新编译/更新二进制后，需要重新运行：
#    ~/.moly/bin/molyd --setup
#    （macOS TCC 将权限绑定到二进制哈希值 — 每次重编译都会使旧授权失效。）
```

### 智能体配置

**所有智能体共用一套 MCP 服务器。** 在智能体的配置文件中加入：

```yaml
# Hermes: ~/.hermes/config.yaml
mcp_servers:
  moly:
    command: python3
    args: ["~/.moly/moly_mcp.py"]
```

```json
// Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json
// OpenClaw: ~/.openclaw/openclaw.json
// Cursor: Settings → MCP
{
  "mcpServers": {
    "moly": {
      "command": "python3",
      "args": ["/path/to/moly_mcp.py"]
    }
  }
}
```

详细配置见 [MCP_SETUP.md](moly-share/MCP_SETUP.md)。

### Chrome 与 Electron 应用用户

Chrome 和 Electron 应用把网页内容渲染在子进程中，需要正确的权限和启动参数。

`molyd --setup` 第 3、4 步会自动处理。配置后：

**Chrome**（AX + 网页捕获）：
```
open -a "Google Chrome" --args \
    --force-renderer-accessibility \
    --remote-debugging-port=9222 \
    --remote-allow-origins=*
```
CDP 端口使 Moly 能提取 `page_url.txt`、`dom.html`（完整 DOM）和 `styles.json`（CSS/配色/字体/布局）。

**Electron 应用**（仅 AX）：
```
open -a "应用名" --args --force-renderer-accessibility
```

验证：`curl -s http://127.0.0.1:19876/axdiag` → `ax_trusted: true`

## 工具列表

| 工具 | 功能 | 使用场景 |
|------|------|---------|
| `take_appshot` | 截取当前前台窗口 | "帮我把终端截个图" |
| `list_appshots` | 浏览截图历史 | "看看最近截了哪些图" |
| `get_appshot` | 获取文本+元数据（~2K tokens）| "这个页面写了什么？" |
| `get_appshot_image` | 获取截图图像（~70K tokens）| "分析这个布局" |
| `search_appshots` | 按关键字搜索 | "找到我的 Spotify 截图" |
| `delete_appshot` | 删除截图 | 清理 |

> 💡 **最快的路径是不经过 API。** 用户粘贴图片时，智能体读 `~/.moly/latest.txt`→ `cat` 本地 JSON 文件。比 MCP 快 100 倍，完全离线可用。

## 架构

```
┌──────────────────────────────────────┐
│          MolyDaemon (:19876)          │
│  Swift, ScreenCaptureKit + AX API    │
│                                      │
│  热键: ⌃⌥⌘Space                     │
│  存储: ~/snapshots/ (SQLite+FS)      │
│  资源: ~/.moly/ (图标、通知等)        │
└──────────────┬───────────────────────┘
               │ HTTP
    ┌──────────┴──────────┐
    ▼                     ▼
  moly_mcp.py        直连调用
  (MCP stdio)        (curl, Python 等)
    │
 ┌──┴──────────────────────┐
 ▼        ▼        ▼       ▼
Hermes  OpenClaw Cursor  Claude
```

## 项目结构

```
moly/
├── capture-daemon/              # Swift 源码
│   ├── Sources/
│   │   ├── MolyDaemon/          # main.swift, CaptureEngine.swift, ...
│   │   └── MolyNotify/          # notify.js, flash.js
│   ├── Package.swift
│   ├── Makefile
│   └── doctor.py
├── moly-share/                  # 分发安装包
│   ├── molyd                    # 预编译二进制
│   ├── install.sh               # 一键安装脚本
│   ├── moly_mcp.py              # MCP 服务器（所有智能体通用）
│   ├── moly_path.py             # PNG 元数据提取工具
│   ├── notify.js / flash.js     # 通知与闪白效果
│   ├── Moly.png / SKILL.md      # 图标与智能体指引
│   └── README.md / INSTALL.md   # 文档
├── LICENSE (MIT)
└── README.md                    # 仓库首页说明
```

## 从源码构建

需要 Xcode Command Line Tools（`xcode-select --install`）：

```bash
cd capture-daemon
make install     # 编译 + 复制到 ~/.moly/bin/molyd
make doctor      # 一键验证
```

## 常见问题

**和 macOS 自带截图工具有什么区别？**  
`Cmd-Shift-4` 只截取像素。Moly 同时截取像素和可访问性文本树——你的智能体不仅能"看见"屏幕，还能"读懂"上面的每一个字。

**可以离线使用吗？**  
可以。所有功能完全本地运行，不需要网络。

**为什么 Chrome 需要额外授权？**  
Chrome 的多进程架构把网页内容 AX 树隔离在 Renderer 子进程中。手动授权 Chrome 辅助功能后，Chrome 才会把网页内容暴露给 AX API。所有 Electron 桌面应用（VS Code、Discord、Slack 等）同理——`molyd --setup` 自动配置它们。

**支持金融/股票类桌面应用吗（Longbridge Pro 等）？**  
支持。Electron 类桌面应用会被 `molyd --setup`（第 4 步）自动检测并配置。配置后需带参数启动：`open -a "应用名" --args --force-renderer-accessibility`。非 Electron 的自定义渲染应用可能无法暴露 AX 树。

**能提取 CSS/样式用于网站复刻吗？**  
能。Chrome 以 `--remote-debugging-port=9222` 参数启动后，Moly 通过 CDP（Chrome DevTools Protocol）自动提取：`page_url.txt`（URL）、`dom.html`（完整 DOM）、`styles.json`（CSS 规则、配色、字体、布局）。智能体获得完整设计层 + AX 文本树，精准复刻网站。无需任何手动浏览器设置。

**智能体如何找到截图数据？**  
首选路径：`cat ~/.moly/latest.txt` 直接返回最新截图目录——一次本地 `cat`，零 HTTP。备用：`python3 ~/.moly/moly_path.py <图片>` 读取 PNG 元数据。降级：`curl http://127.0.0.1:19876/snapshots?limit=1` 通过 daemon API 查询。

**截图保存在哪里？**  
`~/snapshots/<日期>/<ID>/`——每张截图包含 `screenshot.png`、`metadata.json` 和 `accessibility_tree.json`。PNG 文件中嵌入了目录路径元数据，智能体可以直接读取本地文件。

**能改快捷键吗？**  
目前硬编码为 ⌃⌥⌘Space，如需修改请编辑 `HotkeyListener.swift`。

## 开源协议

MIT — 详见 [LICENSE](LICENSE)。

<p align="center">
  <sub>Made with 🐾 by the Moly team</sub>
</p>
