# QClaw Appshots — 安装指南（给智能体看的）

> 这份文档写给 AI 智能体（如 Hermes Agent）阅读。按照文档步骤自动化安装。

---

## 最终效果

安装完成后，获得 5 个工具（toolset: `appshot`）：

| 工具名 | 功能 | 参数 |
|--------|------|------|
| `take_appshot` | 捕获当前前台窗口 | 无 |
| `list_appshots` | 浏览历史快照 | app_name, date_from, date_to, limit, offset |
| `get_appshot` | 获取完整详情（含base64图片） | snapshot_id (必填), include_image, include_ax_tree |
| `search_appshots` | 搜索历史快照 | query (必填), search_in |
| `delete_appshot` | 删除指定快照 | snapshot_id (必填) |

## 核心工作流

由于 `take_appshot` 捕获的是"前台窗口"，而 Hermes 运行在终端里，
所以推荐的用法是 **Hotkey 模式**：

```
用户按快捷键（在 Chrome/Figma 等目标窗口）
    → daemon 在后台捕获（不切到终端）
    → 截图保存到 ~/snapshots/
用户切回 Hermes
    → "分析最新截图"
    → list_appshots(limit=1) → get_appshot(id)
    → 返回分析结果
```

---

## 前置条件检查

逐项检查（遇到未满足的，引导用户操作）：

```
1. macOS 14.0+
   → sw_vers -productVersion

2. Swift 5.9+
   → which swift && swift --version

3. Hermes Agent 已安装
   → ls ~/.hermes/hermes-agent/tools/registry.py

4. 「屏幕录制」权限
   → 系统偏好设置 → 隐私与安全性 → 屏幕录制
   → 勾选运行 daemon 的终端应用

5. 「辅助功能」权限
   → 系统偏好设置 → 隐私与安全性 → 辅助功能
   → 勾选运行 daemon 的终端应用
```

权限无法通过命令行授予，必须引导用户手动操作。

---

## 安装步骤

### 步骤 1: 编译 daemon

```bash
cd <项目目录>/capture-daemon
swift build -c debug
ls -la .build/debug/QClawDaemon
# 预期：约 650KB 的二进制文件
```

### 步骤 2: 复制工具文件到 Hermes

```bash
cp <项目目录>/qclaw-appshot-share/appshot.py ~/.hermes/hermes-agent/tools/appshot.py
ls ~/.hermes/hermes-agent/tools/appshot.py
```

### 步骤 3: 安装 Skill 文件

```bash
mkdir -p ~/.hermes/skills/appshot
cp <项目目录>/qclaw-appshot-share/SKILL.md ~/.hermes/skills/appshot/SKILL.md
```

### 步骤 4: 创建启动守护进程

```bash
DAEMON_BIN="<daemon 编译产物的绝对路径>"

cat > ~/Library/LaunchAgents/com.qclaw.appshot.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.qclaw.appshot</string>
    <key>ProgramArguments</key>
    <array>
        <string>${DAEMON_BIN}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>QCLAW_SNAPSHOT_DIR</key>
        <string>${HOME}/snapshots</string>
        <key>QCLAW_PORT</key>
        <string>19876</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
```

### 步骤 5: 启动 daemon

```bash
launchctl unload ~/Library/LaunchAgents/com.qclaw.appshot.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.qclaw.appshot.plist
sleep 2
```

### 步骤 6: 安装快捷键脚本

```bash
cp <项目目录>/capture-hotkey.sh ~/bin/appshot-capture
chmod +x ~/bin/appshot-capture
```

### 步骤 7: 配置快捷键（引导用户操作）

告诉用户以下内容（这需要用户手动操作）：

**设置快捷键 — 3 种方式任选其一：**

**方式 A: macOS Shortcuts.app（推荐，最简单）**
1. 打开 Shortcuts.app
2. 新建 → 添加 "Run Shell Script" 操作
3. 输入：`~/bin/appshot-capture`
4. 点击右上角 (i) → "在菜单栏中固定" 和 "使用键盘快捷键"
5. 设置快捷键如 `⌃⌥⌘A`

**方式 B: Automator Quick Action**
1. 打开 Automator.app
2. "新建文稿" → "快速操作"
3. 设置："工作流程收到：无输入" / "位于：任何应用程序"
4. 添加 "运行 Shell 脚本" 操作
5. 输入：`~/bin/appshot-capture`
6. 保存为 "Capture Appshot"
7. 系统偏好设置 → 键盘 → 快捷键 → 服务 → 找到 "Capture Appshot" → 设置快捷键

**方式 C: 如果安装了 Raycast / Alfred / Keyboard Maestro**
- 添加一个触发动作，执行 `~/bin/appshot-capture`

### 步骤 8: 验证安装

```bash
# 1. 检查 daemon
curl -s http://127.0.0.1:19876/health
# 预期：{"status":"ok"}

# 2. 测试捕获
~/bin/appshot-capture
# 预期：显示 ✅ <应用名> — <窗口标题> (<字数> chars)
# 同时弹出系统通知
```

### 步骤 9: 重启 Hermes

```bash
pkill -f hermes 2>/dev/null
# 用户重新启动 Hermes
```

---

## 安装后验证

重启 Hermes 后，在对话中测试：

```
请列出现在可用的 appshot 工具
```

应该能看到 5 个工具。

然后测试核心工作流：

1. 切换到 Chrome 或其他应用
2. 按快捷键
3. 切回 Hermes
4. 说 "分析一下我刚截的图"

Hermes 会调用 `list_appshots(limit=1)` 获取最新截图，然后分析。

---

## 目录结构总结

```
~/snapshots/                               # 快照存储
  └── YYYY-MM-DD/
      └── <id>/
          ├── screenshot.png
          ├── accessibility_tree.json
          └── metadata.json

~/Library/LaunchAgents/
  └── com.qclaw.appshot.plist              # Daemon 开机自启

~/bin/
  └── appshot-capture                       # 快捷键触发脚本

~/.hermes/hermes-agent/tools/
  └── appshot.py                           # 工具注册

~/.hermes/skills/appshot/
  └── SKILL.md                             # Skill 说明
```

---

## 故障排查

### 工具不出现
```bash
ls ~/.hermes/hermes-agent/tools/appshot.py
python3 -c "
import sys
sys.path.insert(0, '$HOME/.hermes/hermes-agent')
from tools.appshot import _check_macos_environment
print('health:', _check_macos_environment())
"
```

### 快捷键没反应
```bash
# 手动测试
~/bin/appshot-capture
# 如果手动能工作，快捷键不能 → 检查快捷方式绑定是否正确
```

### 截图总是终端不是目标应用
- 确认是按的**快捷键**而不是在 Hermes 里调用 `take_appshot`
- `take_appshot` 只能在 Hermes/终端本身是目标时使用
- 想要截其他应用 → 必须用快捷键

### 权限问题
```
系统偏好设置 → 隐私与安全性 → 屏幕录制 → 勾选终端
系统偏好设置 → 隐私与安全性 → 辅助功能 → 勾选终端
```
授予后重启 daemon：
```bash
launchctl unload ~/Library/LaunchAgents/com.qclaw.appshot.plist
launchctl load ~/Library/LaunchAgents/com.qclaw.appshot.plist
```
