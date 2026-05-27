---
name: appshot
description: |
  macOS 屏幕截图与窗口上下文捕获。支持两种捕获方式：
  1. Hotkey 模式（推荐）— 用户在目标窗口按快捷键，daemon 捕获后 agent 通过 list_appshots/get_appshot 查询
  2. 直接调用 — take_appshot 捕获当前前台窗口
  适用于用户说"帮我看看这个"、"截图看看"、"这个报错是什么"、"分析最新截图"等场景。
version: 1.3.0
platforms: [macos]
metadata:
  hermes:
    tags: [screenshot, capture, appshot, desktop, macos, vision]
    category: desktop
---

# Appshot — 屏幕截图与窗口上下文

## 核心概念：Hotkey 捕获 vs 直接调用

### 问题：为什么 take_appshot 总是截到终端？

当你通过 Hermes 对话调用 `take_appshot` 时，Hermes 运行在终端里，终端就是"前台窗口"。
所以 `take_appshot` 会截到终端，而不是你正在看的 Chrome/Figma/IDE。

### 解决方案：Hotkey 先捕获，再查询

正确的用法是两步：

```
用户操作（在目标窗口）      Hermes 操作（在对话中）
─────────────────────      ─────────────────────
1. 按快捷键 📸              （daemon 捕获 Chrome）
2. 切回 Hermes 对话         
3. "分析最新截图"           → list_appshots(limit=1)
                            → get_appshot(id, include_image=true)
                            → 返回分析结果
```

## 可用工具

| 工具 | 用途 | 关键参数 |
|------|------|----------|
| `take_appshot` | 捕获当前前台窗口（适合你正在 Hermes 里看的内容） | 无 |
| `list_appshots` | 浏览历史快照、获取最新截图 | app_name, date_from, date_to, limit, offset |
| `get_appshot` | 获取单个快照完整内容（base64图片+AX树+全文） | snapshot_id (必填), include_image, include_ax_tree |
| `search_appshots` | 搜索历史快照 | query (必填), search_in |
| `delete_appshot` | 删除指定快照 | snapshot_id (必填) |

## 何时使用

### 使用 list_appshots + get_appshot（最常用）

当用户说：
- "分析一下我刚截的图"、"看看最新截图"
- "帮我看看这个页面"（用户已在目标窗口按过热键）
- "对比我两次截图"

**操作流程：**
1. `list_appshots(limit=1)` → 获取最新快照 ID
2. 检查 `appName` 是否匹配用户描述的应用
3. `get_appshot(id, include_image=true)` → 获取完整截图和 AX 文本
4. 基于 full_text 分析内容，需要视觉细节时参考 image_base64

### 使用 take_appshot（特定场景）

仅当用户想截的内容就在 Hermes/终端中时使用：
- 用户在终端里跑命令，想让你看输出
- 用户在 Hermes 对话中贴了代码，想让你看整个窗口上下文

### 使用 search_appshots

- "帮我找一下之前截的 Figma 设计稿"
- "搜一下包含 'error' 的截图"

## 使用模式

### 模式 1: Hotkey → 查询（推荐，解决"截到终端"问题）

```
用户按快捷键 → 截图已存入 daemon
用户说 "分析最新截图"
→ list_appshots(limit=1)
→ get_appshot(id, include_image=true)  # 如果需要视觉
→ 基于 full_text 分析并回答
```

### 模式 2: 跨应用对比

```
用户分别在 Chrome、Figma、VS Code 按快捷键
用户说 "对比我最近 3 张截图"
→ list_appshots(limit=3)
→ 分别 get_appshot 获取详情
→ 对比分析
```

### 模式 3: 搜索历史

```
用户说 "搜一下上周的 Figma 截图"
→ search_appshots(query="Figma") 或 list_appshots(app_name="Figma")
→ 列出匹配项
→ get_appshot(id) 获取需要的那个
```

## 重要细节

### list_appshots 返回

- items 按时间倒序排列，第一条就是最新截图
- 每条包含 textPreview（前 500 字符），通常足够判断是否需要进一步获取
- 不包含 base64 图片数据（减少 token 消耗）

### get_appshot 返回

- `image_base64`: base64 编码的 PNG 截图（2048px 宽）
- `full_text`: 从 Accessibility Tree 提取的完整文本
- `accessibility_tree`: 完整的 AX 树 JSON 结构
- `metadata`: 应用名、窗口标题、时间戳等

### 判断需不需要 get_appshot

- 大部分场景 textPreview 足够 — 比如"这是什么应用"、"窗口标题是什么"
- 需要看到具体内容时用 get_appshot — 比如"分析这个页面的布局"、"这个报错的完整内容"

## Fallback

如果 appshot 工具不可用（daemon 未启动、权限未授予），使用系统命令：

```bash
# 截取当前前台窗口
screencapture -w /tmp/window.png
```

配合 `osascript` 获取前台应用信息：
```bash
osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
```

## 仅支持 macOS

本工具仅适用于 macOS 14.0+。需要：
- 后台 daemon 在运行（端口 19876，检查 `curl http://127.0.0.1:19876/health`）
- 终端应用已获得「屏幕录制」和「辅助功能」权限
