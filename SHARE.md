# QClaw Appshots — 分享指南

两个文件 + 一个 daemon = 让你的 Hermes 能"看见"你的屏幕。

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
- Swift 5.9+（`swift build`）
- Hermes Agent 已安装
- 终端.app 需获得 **屏幕录制** + **辅助功能** 权限

### 3. 安装步骤

```bash
cd QClaw-APPScreenshots
chmod +x install.sh
./install.sh
```

脚本自动完成：
1. `swift build` 编译 daemon
2. 复制 `appshot.py` → `~/.hermes/hermes-agent/tools/`
3. 复制 skill → `~/.hermes/skills/appshot/`
4. 创建 LaunchAgent → daemon 开机自启

然后重启 Hermes 即可。

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
