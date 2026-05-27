# QClaw Appshots — 给你的 Hermes 装上"眼睛"

让你能截图 Chrome/Figma/IDE 等任意应用，然后让 Hermes 分析内容。

## 核心用法（30 秒上手）

```
1. 打开 Chrome（或任意目标应用）
2. 按快捷键 ⌃⌥⌘A
3. 切回 Hermes，说 "分析最新截图"
4. Hermes 告诉你能看到什么
```

**为什么不是直接让 Hermes 截图？** 因为 Hermes 跑在终端里，直接调 `take_appshot` 只能截到终端。快捷键方案让你在目标窗口按一下，daemon 在后台捕获，然后 Hermes 通过 `list_appshots` + `get_appshot` 查询结果。

## 文件说明

| 文件 | 给谁 | 用途 |
|------|------|------|
| `SKILL.md` | Hermes 智能体 | 教它 hotkey 工作流和工具用法 |
| `INSTALL.md` | Hermes 智能体 | 自动安装指南 |
| `appshot.py` | Hermes 工具系统 | 5 个工具注册（放到 tools/ 目录） |
| `capture-hotkey.sh` | 用户 | 快捷键触发脚本 |
| `README.md` | 人类 | 这份文件 |

## 安装

### 给人类看（手动 3 步）

```bash
# 1. 编译 daemon
cd ../capture-daemon && swift build -c debug

# 2. 复制文件
cp appshot.py ~/.hermes/hermes-agent/tools/
mkdir -p ~/.hermes/skills/appshot && cp SKILL.md ~/.hermes/skills/appshot/
cp capture-hotkey.sh ~/bin/appshot-capture && chmod +x ~/bin/appshot-capture

# 3. 启动 daemon
QCLAW_SNAPSHOT_DIR="$HOME/snapshots" QCLAW_PORT=19876 \
  ../capture-daemon/.build/debug/QClawDaemon &
```

然后设置快捷键（Shortcuts.app 或 Automator，详见 INSTALL.md 步骤 7），重启 Hermes。

### 给 Hermes 自动装

把 `INSTALL.md` 的内容发给 Hermes，说：

> 请按照这个文档，帮我安装 QClaw Appshots 插件

Hermes 会自动执行除快捷键绑定外的所有步骤。

### 前置条件

- macOS 14.0+、Swift 5.9+、Hermes Agent
- 系统偏好设置 → 屏幕录制 + 辅助功能 → 勾选终端
