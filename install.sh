#!/bin/bash
# Molys — Hermes 插件一键安装脚本
# 用法: chmod +x install.sh && ./install.sh
set -e

echo "=== Molys for Hermes ==="

# ── 1. Build daemon ──
echo ""
echo "[1/4] Building capture daemon..."
DAEMON_DIR="$(cd "$(dirname "$0")/capture-daemon" && pwd)"
cd "$DAEMON_DIR"
swift build -c debug --quiet 2>&1 | tail -1
DAEMON_BIN="$DAEMON_DIR/.build/debug/MolyDaemon"
echo "  → $DAEMON_BIN"

# ── 2. Install Hermes tool ──
echo ""
echo "[2/4] Installing Hermes tool..."
TOOLS_DIR="$HOME/.hermes/hermes-agent/tools"
mkdir -p "$TOOLS_DIR"
cp "$(dirname "$0")/hermes-plugin/tools/appshot.py" "$TOOLS_DIR/appshot.py"
echo "  → $TOOLS_DIR/appshot.py"

# ── 3. Install Skill ──
echo ""
echo "[3/4] Installing skill..."
SKILL_DIR="$HOME/.hermes/skills/appshot"
mkdir -p "$SKILL_DIR"
cp "$(dirname "$0")/hermes-plugin/skills/appshot-context.md" "$SKILL_DIR/SKILL.md"
echo "  → $SKILL_DIR/SKILL.md"

# ── 4. Create launch script ──
echo ""
echo "[4/4] Creating launch agent..."
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.moly.daemon.plist"
cat > "$LAUNCH_AGENT" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.moly.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DAEMON_BIN</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>MOLY_SNAPSHOT_DIR</key>
        <string>$HOME/snapshots</string>
        <key>MOLY_PORT</key>
        <string>19876</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST
echo "  → $LAUNCH_AGENT"

# ── Start daemon ──
echo ""
echo "Starting daemon..."
launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
launchctl load "$LAUNCH_AGENT"
sleep 2

# ── Verify ──
echo ""
if curl -s http://127.0.0.1:19876/health | grep -q ok; then
    echo "✅ Daemon running on port 19876"
else
    echo "⚠️  Daemon may not have started — check permissions:"
    echo "   系统偏好设置 → 隐私与安全性 → 屏幕录制"
    echo "   系统偏好设置 → 隐私与安全性 → 辅助功能"
fi

echo ""
echo "=== 安装完成 ==="
echo "重启 Hermes 后即可使用。测试: 在 Hermes 对话中输入「帮我截个图」"
