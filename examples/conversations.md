# QClaw Appshots — 对话示例

## 示例 1: Hermes Agent 调试浏览器报错

```
User: 帮我看看浏览器里这个报错是什么原因

Hermes Agent:
  → 调用 tool: take_appshot()
  → 返回: {
      "app_name": "Google Chrome",
      "window_title": "localhost:3000 — Console",
      "text_preview": "[AXStaticText] Uncaught TypeError: Cannot read properties...",
      ...
    }

Agent: 我看到你的浏览器控制台有一个 TypeError。
      让我获取完整的错误信息。

  → 调用 tool: get_appshot(snapshot_id, include_image=true)

Agent: 错误是 `Uncaught TypeError: Cannot read properties of undefined
       (reading 'map')`，发生在 app.js:42。
       这通常是因为你在对一个 undefined 值调用 .map()。
       让我检查一下代码...

  → 调用 tool: read_file("src/app.js")

Agent: 找到问题了。第 42 行的 `data.items.map(...)` 没有做 null check。
      因为 API 返回的 data 中 items 字段可能为 undefined。
      已为你修复。
```

## 示例 2: OpenClaw 分析设计稿

```
User: 这是我在 Figma 里做的登录页设计，帮我生成对应的 React 组件

OpenClaw:
  → 调用 tool: qclaw-appshot_take_appshot()
  → 获取 Figma 窗口截图 + 设计元素文本

  → 返回: {
      "app_name": "Figma",
      "window_title": "Login Page — Design",
      "text_preview": "[AXTextField] Email address | [AXTextField] Password |
                       [AXButton] Sign In | [AXStaticText] Forgot password?...",
      ...
    }

OpenClaw:
  我分析了你的 Figma 设计，生成了对应的 React 组件。
  设计稿包含以下元素:
  - Email 输入框 (带 "Email address" 占位符)
  - Password 输入框 (带 "Password" 占位符)
  - Sign In 按钮 (蓝色主色调)
  - "Forgot password?" 链接

  [生成的 JSX 代码...]
```

## 示例 3: 连续多应用快照

```
User: 帮我对比一下 PR #342 在 GitHub 和本地代码里的差异

Agent:
  → take_appshot()  → Chrome/GitHub PR 页面
  → take_appshot()  → VS Code/本地 diff 视图
  → list_appshots(limit=2)

Agent:
  我抓取了两个窗口的快照:
  1. GitHub PR #342 (Chrome) — 新增了 auth middleware
  2. VS Code diff (本地) — 显示相同的修改

  两边内容一致，PR 可以合并。
```
