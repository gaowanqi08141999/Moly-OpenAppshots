# QClaw Appshots — 分享指南

两个文件 + 一个 daemon = 让你的 Hermes 能"看见"你的屏幕。

## 新特性

1. **截图即复制** — 按热键截图后，PNG **自动复制到系统剪贴板**。直接 ⌘V 粘贴到任何对话框。
2. **内置热键** — daemon 原生监听 ⌃⌥⌘Space，**不需要 Shortcuts.app 配置**。
3. **一键安装** — `chmod +x install.sh && ./install.sh` 搞定一切。

## 你需要给你的朋友

### 1. 整个项目文件夹（或至少这三个东西）

```
QClaw-APPScreenshots/
├── install.sh                          # 一键安装
├── capture-daemon/                     # Swift daemon 源码
├── hermes-plugin/tools/appshot.py      # Hermes 工具注册（单文件）
└── hermes-plugin/skills/appshot-context.md  # Skill
```

### 2. 前提条件

你朋友的 Mac 需要：
- macOS 14+（ScreenCaptureKit 要求）
- Hermes Agent 已安装
- **屏幕录制** + **辅助功能** 权限（安装时会引导开启）

> 不需要 Swift/Xcode！安装包包含预编译好的 `QClawDaemon` 二进制。

### 3. 安装步骤

```bash
cd qclaw-appshot-share
chmod +x install.sh
./install.sh
```

脚本自动完成：
1. 复制预编译 daemon → `~/.qclaw/bin/qclawd`
2. 复制通知资源 → `~/.qclaw/`
3. 复制 `appshot.py` → `~/.hermes/tools/`
4. 复制 skill → `~/.hermes/skills/appshot/`
5. 创建 LaunchAgent → daemon 开机自启

然后按提示开启权限，重启 Hermes 即可。

### 4. 使用

- **⌃⌥⌘Space** 截图（任何窗口）→ 通知弹窗 → 图片入剪贴板 → ⌘V 粘贴
- 或在 Hermes 中说 `"帮我截个图"` → `"分析最新截图"`

### 4. 验证

在 Hermes 对话中输入：
```
帮我截个图，看看我现在在做什么
```

Hermes 会调用 `take_appshot`，返回应用名、窗口标题和文本预览。

---

## 手动安装（如果脚本跑不通）

### 步骤 1: 编译 daemon
```bash
cd capture-daemon
swift build -c debug
```

### 步骤 2: 复制两个文件
```bash
cp hermes-plugin/tools/appshot.py ~/.hermes/hermes-agent/tools/
mkdir -p ~/.hermes/skills/appshot
cp hermes-plugin/skills/appshot-context.md ~/.hermes/skills/appshot/SKILL.md
```

### 步骤 3: 启动 daemon
```bash
QCLAW_SNAPSHOT_DIR="$HOME/snapshots" \
QCLAW_PORT=19876 \
./capture-daemon/.build/debug/QClawDaemon &
```

### 步骤 4: 授予权限
系统偏好设置 → 隐私与安全性 → 屏幕录制 → 勾选终端
系统偏好设置 → 隐私与安全性 → 辅助功能 → 勾选终端

### 步骤 5: 重启 Hermes

---

## 故障排查

| 症状 | 原因 | 解决 |
|------|------|------|
| 工具不出现 | `appshot.py` 没放对位置 | 检查 `ls ~/.hermes/hermes-agent/tools/appshot.py` |
| 捕获超时 | 没给屏幕录制权限 | 系统偏好设置 → 屏幕录制 |
| AX 树为空 | 没给辅助功能权限 | 系统偏好设置 → 辅助功能 |
| 连接被拒 | daemon 没启动 | `curl http://127.0.0.1:19876/health` |

---

## 架构（一图胜千言）

```
Hermes Agent
  │
  ├─ tools/appshot.py  ←──HTTP──→  QClawDaemon (:19876)
  │   (5 tools)                         │
  │                                ScreenCaptureKit  →  PNG
  └─ skills/appshot/               Accessibility API →  Text Tree
      SKILL.md                      SQLite            →  ~/snapshots/
```
