#!/bin/bash
# Moly — One-click installer for friends
# Usage: chmod +x install.sh && ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_BIN="${SCRIPT_DIR}/molyd"
INSTALL_DIR="$HOME/.moly"
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
print_step "Installing MolyDaemon..."

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin"

if [[ -f "$DAEMON_BIN" ]]; then
    # Pre-built binary included
    cp "$DAEMON_BIN" "$INSTALL_DIR/bin/molyd"
    chmod +x "$INSTALL_DIR/bin/molyd"
    # Permanent ad-hoc signature — prevents macOS from revoking permissions on upgrade
    codesign --force --sign - "$INSTALL_DIR/bin/molyd" 2>/dev/null || true
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
    cp ".build/release/MolyDaemon" "$INSTALL_DIR/bin/molyd"
    chmod +x "$INSTALL_DIR/bin/molyd"
    codesign --force --sign - "$INSTALL_DIR/bin/molyd" 2>/dev/null || true
fi

# Add to PATH if not already
if ! grep -q "$INSTALL_DIR/bin" "$HOME/.zshrc" 2>/dev/null; then
    echo "export PATH=\"$INSTALL_DIR/bin:\$PATH\"" >> "$HOME/.zshrc"
    print_step "Added ~/.moly/bin to PATH (restart terminal to use 'molyd' directly)"
fi

# ── Enable Chrome accessibility (Chrome lazily builds AX trees) ──
if [[ -f "/Applications/Google Chrome.app/Contents/Info.plist" ]]; then
    print_step "Enabling Chrome accessibility mode..."
    defaults write com.google.Chrome AXManualAccessibility -bool true 2>/dev/null || true
    print_step "Chrome AX mode enabled. Restart Chrome for it to take effect."
fi

# ── Install notification assets ──
print_step "Installing notification assets..."

if [[ -f "${SCRIPT_DIR}/notify.js" ]]; then
    cp "${SCRIPT_DIR}/notify.js" "$INSTALL_DIR/notify.js"
fi
if [[ -f "${SCRIPT_DIR}/flash.js" ]]; then
    cp "${SCRIPT_DIR}/flash.js" "$INSTALL_DIR/flash.js"
fi
if [[ -f "${SCRIPT_DIR}/Moly.png" ]]; then
    cp "${SCRIPT_DIR}/Moly.png" "$INSTALL_DIR/Moly.png"
fi
if [[ -f "${SCRIPT_DIR}/moly_path.py" ]]; then
    cp "${SCRIPT_DIR}/moly_path.py" "$INSTALL_DIR/moly_path.py"
fi

# ── Install MCP server (unified tool layer for ALL agents) ──
print_step "Installing MCP server..."

if [[ -f "${SCRIPT_DIR}/moly_mcp.py" ]]; then
    cp "${SCRIPT_DIR}/moly_mcp.py" "$INSTALL_DIR/moly_mcp.py"
fi

# ── Install skill files ──
# Deploy SKILL.md to all detected AI agents so they auto-discover Moly usage rules.
# Each agent has its own skill directory convention — we handle them all here.
print_step "Installing skill files to all detected AI agents..."

# Canonical location (always installed)
MOLY_CANONICAL_SKILL_DIR="$INSTALL_DIR/skills/moly"
mkdir -p "$MOLY_CANONICAL_SKILL_DIR"
cp "${SCRIPT_DIR}/SKILL.md" "$MOLY_CANONICAL_SKILL_DIR/SKILL.md"

# Helper: deploy skill to a target directory
deploy_skill() {
    local target_dir="$1"
    local agent_name="$2"
    mkdir -p "$target_dir"
    cp "${SCRIPT_DIR}/SKILL.md" "$target_dir/SKILL.md"
    print_step "  $agent_name → $target_dir/SKILL.md"
}

# Detect and deploy to each agent
AGENTS_CONFIGURED=()

# Hermes
if [[ -d "$HOME/.hermes/skills" ]]; then
    deploy_skill "$HOME/.hermes/skills/appshot" "Hermes"
    AGENTS_CONFIGURED+=("Hermes")
fi

# Codex / WorkBuddy
if [[ -d "$HOME/.codex/skills" ]]; then
    deploy_skill "$HOME/.codex/skills/moly" "Codex"
    AGENTS_CONFIGURED+=("Codex")
fi

# OpenClaw
if [[ -d "$HOME/.openclaw/skills" ]]; then
    deploy_skill "$HOME/.openclaw/skills/moly" "OpenClaw"
    AGENTS_CONFIGURED+=("OpenClaw")
fi

# Claude Code — deploy to project's .claude/skills/ so Claude auto-discovers it
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLAUDE_SKILLS_DIR="${PROJECT_ROOT}/.claude/skills/moly"
if [[ -d "$(dirname "$CLAUDE_SKILLS_DIR")" ]] || true; then
    # Always create — even if .claude/ doesn't exist yet, because user might use Claude Code later
    mkdir -p "$CLAUDE_SKILLS_DIR"
    cp "${SCRIPT_DIR}/SKILL.md" "$CLAUDE_SKILLS_DIR/SKILL.md"
    print_step "  Claude Code (project) → $CLAUDE_SKILLS_DIR/SKILL.md"
    AGENTS_CONFIGURED+=("Claude Code")
fi

# Also deploy to ~/.claude/skills/ for global Claude Code access
if [[ -d "$HOME/.claude/skills" ]]; then
    deploy_skill "$HOME/.claude/skills/moly" "Claude Code (global)"
elif [[ -d "$HOME/.claude" ]]; then
    mkdir -p "$HOME/.claude/skills/moly"
    cp "${SCRIPT_DIR}/SKILL.md" "$HOME/.claude/skills/moly/SKILL.md"
    print_step "  Claude Code (global) → ~/.claude/skills/moly/SKILL.md"
fi

if [[ ${#AGENTS_CONFIGURED[@]} -gt 0 ]]; then
    print_step "Skills deployed for: ${AGENTS_CONFIGURED[*]}"
else
    print_warn "No known AI agents detected. Skill installed to $MOLY_CANONICAL_SKILL_DIR only."
    print_warn "Your agent may need manual skill configuration."
fi

# ── Configure MCP servers for each agent ──
print_step "Configuring MCP servers..."

# Hermes MCP
if [[ -f "$HOME/.hermes/config.yaml" ]]; then
    if grep -q "moly" "$HOME/.hermes/config.yaml" 2>/dev/null; then
        print_step "  Hermes MCP already configured."
    elif command -v hermes &> /dev/null; then
        hermes mcp add moly -- python3 "$INSTALL_DIR/moly_mcp.py" 2>/dev/null && \
            print_step "  Hermes MCP configured via 'hermes mcp add'." || \
            print_warn "  Hermes: run 'hermes mcp add moly -- python3 $INSTALL_DIR/moly_mcp.py'"
    else
        print_warn "  Hermes CLI not in PATH. Add manually later:"
        print_warn "    hermes mcp add moly -- python3 $INSTALL_DIR/moly_mcp.py"
    fi
fi

# OpenClaw MCP
if [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
    if grep -q "moly" "$HOME/.openclaw/openclaw.json" 2>/dev/null; then
        print_step "  OpenClaw MCP already configured."
    elif command -v openclaw &> /dev/null; then
        openclaw mcp add moly -- python3 "$INSTALL_DIR/moly_mcp.py" 2>/dev/null && \
            print_step "  OpenClaw MCP configured via 'openclaw mcp add'." || \
            print_warn "  OpenClaw: run 'openclaw mcp add moly -- python3 $INSTALL_DIR/moly_mcp.py'"
    fi
fi

# Claude Code MCP — if Claude Desktop config exists
CLAUDE_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
if [[ -f "$CLAUDE_CONFIG" ]]; then
    if command -v python3 &> /dev/null; then
        python3 -c "
import json, sys
try:
    with open('$CLAUDE_CONFIG') as f: cfg = json.load(f)
    servers = cfg.setdefault('mcpServers', {})
    if 'moly' not in servers:
        servers['moly'] = {'command': 'python3', 'args': ['$INSTALL_DIR/moly_mcp.py']}
        with open('$CLAUDE_CONFIG', 'w') as f: json.dump(cfg, f, indent=2)
        print('  Claude Desktop MCP configured.')
    else:
        print('  Claude Desktop MCP already configured.')
except Exception as e:
    print(f'  Claude Desktop MCP setup skipped: {e}')
" 2>/dev/null
    fi
fi

# ── Create LaunchAgent (auto-start on login) ──
print_step "Setting up auto-start..."

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS_DIR"

cat > "$LAUNCH_AGENTS_DIR/com.moly.daemon.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.moly.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/bin/molyd</string>
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

launchctl load "$LAUNCH_AGENTS_DIR/com.moly.daemon.plist" 2>/dev/null || true

# Start daemon now
"$INSTALL_DIR/bin/molyd" &
sleep 2

# ── Verify ──
print_step "Verifying installation..."

if curl -s http://127.0.0.1:19876/health | grep -q '"status":"ok"'; then
    print_step "Daemon is running!"
else
    print_warn "Daemon may need permissions first. See below."
fi

# ── Permission Setup (interactive wizard) ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Installation complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Now running the ONE-TIME permission setup wizard..."
echo ""

# Run the setup wizard
"$INSTALL_DIR/bin/molyd" --setup

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}All set!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Hotkey: ⌃⌥⌘Space — capture any window."
echo "Verify: cd capture-daemon && make doctor"
echo ""

# ── Optional: Chrome reminder ──
if [[ "$(defaults read com.google.Chrome AXManualAccessibility 2>/dev/null)" == "1" ]]; then
    echo -e "${GREEN}Chrome AX mode enabled.${NC}"
    echo "⚠️  Remember: ⌘Q quit Chrome and reopen to activate AX bridge."
fi
