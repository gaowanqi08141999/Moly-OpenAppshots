# 将 QClaw Appshots 接入 Hermes Agent

> 适用版本: Hermes Agent v0.13.0+

---

## 前置条件

- [x] Swift daemon 已编译: `capture-daemon/.build/debug/QClawDaemon`
- [x] macOS Screen Recording + Accessibility 权限已授予
- [x] Daemon 已在后台运行（端口 19876）

---

## 步骤 1: 创建 daemon 启动脚本

```bash
cat > /Users/jane/Desktop/QClaw-APPScreenshots/start-daemon.sh << 'SCRIPT'
#!/bin/bash
DAEMON="/Users/jane/Desktop/QClaw-APPScreenshots/capture-daemon/.build/debug/QClawDaemon"
SNAPSHOT_DIR="$HOME/snapshots"
PORT="${QCLAW_PORT:-19876}"

pkill -f QClawDaemon 2>/dev/null
sleep 1

QCLAW_SNAPSHOT_DIR="$SNAPSHOT_DIR" QCLAW_PORT="$PORT" "$DAEMON" &
echo "QClaw Daemon started on http://127.0.0.1:$PORT"
SCRIPT
chmod +x /Users/jane/Desktop/QClaw-APPScreenshots/start-daemon.sh
```

## 步骤 2: 复制工具文件到 Hermes

工具文件使用 Hermes 原生的 `registry.register()` 机制，通过 HTTP 直接调用 daemon，**无需 MCP**：

```bash
cp hermes-plugin/tools/appshot.py ~/.hermes/hermes-agent/tools/appshot.py
```

Hermes 会在启动时通过 AST 自动发现并注册这 5 个工具：
- `take_appshot` — 捕获前台窗口
- `list_appshots` — 浏览历史快照
- `get_appshot` — 获取完整快照详情
- `search_appshots` — 搜索快照
- `delete_appshot` — 删除快照

## 步骤 3: 创建 Skill 文件

```bash
mkdir -p ~/.hermes/skills/appshot
```

创建 `~/.hermes/skills/appshot/SKILL.md`（内容见 `hermes-plugin/skills/appshot-context.md`）

## 步骤 4: 启动并验证

```bash
# 1. 启动 daemon
/Users/jane/Desktop/QClaw-APPScreenshots/start-daemon.sh

# 2. 验证 daemon 健康
curl http://127.0.0.1:19876/health
# → {"status":"ok"}

# 3. 重启 Hermes
pkill -f "hermes" 2>/dev/null
# 然后重新启动 hermes

# 4. 在 Hermes 中检查工具是否加载
hermes tools list 2>/dev/null | grep appshot
# 应该看到 5 个 appshot 工具
```

## 步骤 5: 在 Hermes 对话中测试

```
请帮我截取当前屏幕，看看我在做什么
```

Hermes 会：
1. 调用 `take_appshot`
2. 返回应用名、窗口标题、文本预览
3. AI 根据上下文做出回应

---

## 故障排查

### 工具不出现
```bash
# 检查文件是否在正确位置
ls ~/.hermes/hermes-agent/tools/appshot.py

# 手动测试注册
cd ~/.hermes/hermes-agent
./venv/bin/python -c "
from tools.registry import discover_builtin_tools
discover_builtin_tools()
from tools.registry import registry
print([n for n in registry.get_all_tool_names() if 'appshot' in n])
"
```

### 捕获失败
```bash
# 检查 daemon 是否在运行
curl http://127.0.0.1:19876/health

# 重启 daemon
/Users/jane/Desktop/QClaw-APPScreenshots/start-daemon.sh
```

### 权限问题
```
系统偏好设置 → 隐私与安全性 → 屏幕录制 → 勾选终端.app
系统偏好设置 → 隐私与安全性 → 辅助功能 → 勾选终端.app
```

---

## 架构总览

```
Hermes Agent
    │
    ├─ tools/appshot.py (registry.register × 5)
    │     │
    │     └─ HTTP → Daemon (Swift, TCP :19876)
    │               ├─ ScreenCaptureKit → PNG 截图
    │               ├─ Accessibility API → 结构化文本
    │               └─ Storage → ~/snapshots/
    │
    └─ skills/appshot/SKILL.md
          │
          └─ 教 Agent 何时使用 + 使用模式
```

对比 MCP 方案的优势：零协议依赖、零进程启动开销、直接 HTTP 调用更可靠。
