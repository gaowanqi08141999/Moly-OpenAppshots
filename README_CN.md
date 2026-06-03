<img src="https://raw.githubusercontent.com/gaowanqi08141999/moly/main/cover.png" style="display:none">

# Moly — 面向 AI 智能体的开源截图工具

[English](README.md) | [中文](README_CN.md)

> *一只聪明的小猫，看见你的屏幕，告诉 AI 一切。*

**Moly** 一键捕获 macOS 屏幕——截图 + 可访问性文本树——通过标准 MCP 协议喂给任何 AI 智能体。

### Moly 做什么

- **一键截图（⌃⌥⌘Space）**：同时捕获前台窗口的两层信息
- **视觉层**：Retina 2x PNG 高清截图，通过 macOS ScreenCaptureKit 获取
- **文本层**：完整的可访问性元素树——智能体可以读取屏幕上的每一个标签、按钮和段落
- **剪贴板自动复制**：截图自动入剪贴板，⌘V 直接粘贴
- **零 API 调用**：粘贴的 PNG 携带嵌入式元数据指向本地文件路径，智能体直接读磁盘，毫秒级完成

### 实现原理

1. 一个轻量级 Swift daemon（`~/.moly/bin/molyd`）在本地 19876 端口运行
2. 通过 CGEvent tap 全局监听 ⌃⌥⌘Space 快捷键
3. 截图时获取前台窗口 PID，ScreenCaptureKit 截图，同时遍历窗口的可访问性元素树
4. 两者保存到 `~/snapshots/<日期>/<ID>/`，由 SQLite 索引
5. PNG 嵌入 `moly_path` 元数据指向其快照目录，然后复制到剪贴板
6. Python MCP 服务器（`moly_mcp.py`）通过 stdio JSON-RPC 暴露 5 个工具——任何 MCP 兼容的智能体都能调用
7. 如果用户粘贴图片，智能体从 PNG 中提取 `moly_path`，直接读取本地 JSON 文件——无需 API 调用

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![MCP](https://img.shields.io/badge/MCP-compatible-purple)](https://modelcontextprotocol.io/)

## 工作原理

```
你按下 ⌃⌥⌘Space
        │
        ▼
┌──────────────────┐
│  ScreenCaptureKit │  →  Retina 2x PNG 截图
│  Accessibility API│  →  结构化文本树 (AX)
└────────┬─────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
 ~/snapshots/   剪贴板（PNG 含嵌入式元数据）
    │              │
    ▼              ▼
  MCP 服务器    智能体解析
  (5 个工具)    元数据直达本地文件
    │              │
    └──────┬───────┘
           ▼
     智能体分析一切
```

**一键截图。PNG 入剪贴板。文本树落盘。智能体两者皆读。**

## 特性

- **⌃⌥⌘Space 快捷键** — daemon 内置，无需 Shortcuts.app
- **双重捕获** — Retina PNG 截图 + 完整 AX 文本树，一次完成
- **剪贴板自动复制** — 截图后直接 ⌘V 粘贴到任意对话框
- **PNG 元数据嵌入** — 粘贴的图片携带本地文件路径，智能体直接读取本地 JSON，0 次 API 调用
- **统一 MCP** — 一套工具适配 Hermes、OpenClaw、Claude Desktop、Cursor 及任何 MCP 客户端
- **Apple 风格通知** — 右上角白色圆角弹窗，带自定义图标
- **屏幕闪白** — 截图瞬间的视觉反馈
- **100% 本地** — 不上传云端，不需要 API key，不需要网络

## 快速开始

```bash
# 1. 下载安装
git clone https://github.com/gaowanqi08141999/moly.git
cd moly/moly-share
chmod +x install.sh && ./install.sh

# 2. 授予权限（必须，一次性操作）
#    系统设置 → 隐私与安全性
#    → 屏幕录制  → + → ⌘⇧G → ~/.moly/bin/molyd
#    → 辅助功能  → + → ⌘⇧G → ~/.moly/bin/molyd

# 3. 重启 daemon
killall molyd; sleep 1; ~/.moly/bin/molyd &

# 4. 验证
cd ../capture-daemon && make doctor
# → ✅ Daemon running / ✅ AX trusted / ✅ Capture OK

# 5. 配置智能体的 MCP 服务器（一次性，见下文）

# 6. 搞定！在任意窗口按 ⌃⌥⌘Space，⌘V 粘贴给智能体
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

### Chrome 用户

Chrome 的网页内容需要额外授权辅助功能：

- 系统设置 → 隐私与安全性 → 辅助功能 → **+** → Google Chrome → 勾选
- ⌘Q 完全退出 Chrome，重新打开（激活 AX 桥接必须重启）

## 工具列表

| 工具 | 功能 | 使用场景 |
|------|------|---------|
| `take_appshot` | 截取当前前台窗口 | "帮我把终端截个图" |
| `list_appshots` | 浏览截图历史 | "看看最近截了哪些图" |
| `get_appshot` | 获取文本+元数据（~2K tokens）| "这个页面写了什么？" |
| `get_appshot_image` | 获取截图图像（~70K tokens）| "分析这个布局" |
| `search_appshots` | 按关键字搜索 | "找到我的 Spotify 截图" |
| `delete_appshot` | 删除截图 | 清理 |

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
Chrome 的多进程架构把网页内容 AX 树隔离在 Renderer 子进程中。手动授权 Chrome 辅助功能后，Chrome 才会把网页内容暴露给 AX API。

**截图保存在哪里？**  
`~/snapshots/<日期>/<ID>/`——每张截图包含 `screenshot.png`、`metadata.json` 和 `accessibility_tree.json`。PNG 文件中嵌入了目录路径元数据，智能体可以直接读取本地文件。

**能改快捷键吗？**  
目前硬编码为 ⌃⌥⌘Space，如需修改请编辑 `HotkeyListener.swift`。

## 开源协议

MIT — 详见 [LICENSE](LICENSE)。

<p align="center">
  <sub>Made with 🐾 by the Moly team</sub>
</p>
