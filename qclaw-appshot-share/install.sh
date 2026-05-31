#!/bin/bash
# QClaw Appshot — One-click installer for friends
# Usage: chmod +x install.sh && ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_BIN="${SCRIPT_DIR}/QClawDaemon"
INSTALL_DIR="$HOME/.qclaw-appshot"
HERMES_SKILLS_DIR="$HOME/.hermes/skills/appshot"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# ── Check prerequisites ──
print_step "Checking prerequisites..."

if [[ "$(uname)" != "Darwin" ]]; then
    print_error "This tool only works on macOS."
    exit 1
fi

# Check macOS version (need 14+)
OS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$OS_MAJOR" -lt 14 ]]; then
    print_error "macOS 14.0+ required. You have $(sw_vers -productVersion)"
    exit 1
fi

# Check if Hermes is installed
if [[ ! -d "$HOME/.hermes" ]]; then
    print_warn "Hermes Agent not found at ~/.hermes"
    print_warn "Please install Hermes first, then re-run this installer."
    echo "   → Continue anyway? (y/n)"
    read -r CONTINUE
    if [[ "$CONTINUE" != "y" ]]; then
        exit 1
    fi
fi

# ── Install daemon ──
print_step "Installing QClawDaemon..."

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin"

if [[ -f "$DAEMON_BIN" ]]; then
    # Pre-built binary included
    cp "$DAEMON_BIN" "$INSTALL_DIR/bin/qclawd"
    chmod +x "$INSTALL_DIR/bin/qclawd"
    print_step "Installed pre-built binary."
else
    # Need to compile
    print_warn "Pre-built binary not found. Attempting to compile..."
    if ! command -v swift &> /dev/null; then
        print_error "Swift not found. Please install Xcode Command Line Tools:"
        print_error "   xcode-select --install"
        exit 1
    fi
    cd "${SCRIPT_DIR}/capture-daemon" 2>/dev/null || {
        print_error "Daemon source not found. Cannot compile."
        exit 1
    }
    swift build -c release
    cp ".build/release/QClawDaemon" "$INSTALL_DIR/bin/qclawd"
    chmod +x "$INSTALL_DIR/bin/qclawd"
fi

# Add to PATH if not already
if ! grep -q "$INSTALL_DIR/bin" "$HOME/.zshrc" 2>/dev/null; then
    echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> "$HOME/.zshrc"
    print_step "Added ~/.qclaw-appshot/bin to PATH (restart terminal to use 'qclawd' directly)"
fi

# ── Install notification assets ──
print_step "Installing notification assets..."

if [[ -f "${SCRIPT_DIR}/notify.js" ]]; then
    cp "${SCRIPT_DIR}/notify.js" "$INSTALL_DIR/notify.js"
fi
if [[ -f "${SCRIPT_DIR}/flash.js" ]]; then
    cp "${SCRIPT_DIR}/flash.js" "$INSTALL_DIR/flash.js"
fi
if [[ -f "${SCRIPT_DIR}/QClaw.png" ]]; then
    cp "${SCRIPT_DIR}/QClaw.png" "$INSTALL_DIR/QClaw.png"
fi
if [[ -f "${SCRIPT_DIR}/qclaw_path.py" ]]; then
    cp "${SCRIPT_DIR}/qclaw_path.py" "$INSTALL_DIR/qclaw_path.py"
fi

# ── Install MCP server (unified tool layer for ALL agents) ──
print_step "Installing MCP server..."

if [[ -f "${SCRIPT_DIR}/appshot_mcp.py" ]]; then
    cp "${SCRIPT_DIR}/appshot_mcp.py" "$INSTALL_DIR/appshot_mcp.py"
fi

# ── Install skill files ──
print_step "Installing skill files..."

mkdir -p "$HERMES_SKILLS_DIR"
cp "${SCRIPT_DIR}/SKILL.md" "$HERMES_SKILLS_DIR/"

# Also copy to QClaw skills dir if it exists
QCLAW_SKILLS_DIR="$HOME/.qclaw/skills/qclaw-appshot"
if [[ -d "$HOME/.qclaw/skills" ]]; then
    mkdir -p "$QCLAW_SKILLS_DIR"
    cp "${SCRIPT_DIR}/SKILL.md" "$QCLAW_SKILLS_DIR/"
fi

# ── Configure Hermes MCP (if Hermes is installed) ──
if [[ -f "$HOME/.hermes/config.yaml" ]]; then
    print_step "Configuring Hermes MCP..."
    if ! grep -q "qclaw-appshot" "$HOME/.hermes/config.yaml" 2>/dev/null; then
        print_warn "Please run: hermes mcp add qclaw-appshot -- python3 $INSTALL_DIR/appshot_mcp.py"
    else
        print_step "Hermes MCP already configured."
    fi
fi

# ── Create LaunchAgent (auto-start on login) ──
print_step "Setting up auto-start..."

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS_DIR"

cat > "$LAUNCH_AGENTS_DIR/com.qclaw.daemon.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.qclaw.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/bin/qclawd</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/daemon.log</string>
</dict>
</plist>
EOF

launchctl load "$LAUNCH_AGENTS_DIR/com.qclaw.daemon.plist" 2>/dev/null || true

# Start daemon now
"$INSTALL_DIR/bin/qclawd" &
sleep 2

# ── Verify ──
print_step "Verifying installation..."

if curl -s http://127.0.0.1:19876/health | grep -q '"status":"ok"'; then
    print_step "Daemon is running!"
else
    print_warn "Daemon may need permissions first. See below."
fi

# ── Permissions reminder ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Installation complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "You MUST grant these permissions (one-time setup):"
echo ""
echo "1. Screen Recording:"
echo "   System Settings → Privacy & Security → Screen Recording"
echo "   → + → ⌘⇧G → ${INSTALL_DIR}/bin/qclawd → Open → Toggle ON"
echo ""
echo "2. Accessibility:"
echo "   System Settings → Privacy & Security → Accessibility"
echo "   → + → ⌘⇧G → ${INSTALL_DIR}/bin/qclawd → Open → Toggle ON"
echo ""
echo "3. Restart the daemon after granting permissions:"
echo "   killall qclawd; ${INSTALL_DIR}/bin/qclawd &"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Hotkey is ready!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Press ⌃⌥⌘Space to capture any window."
echo "The screenshot PNG is automatically copied to your clipboard."
echo ""
echo "Then restart Hermes and try: 'Take an appshot'"
echo ""
