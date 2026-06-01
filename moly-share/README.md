# Moly — macOS Screenshot + Accessibility Text Capture

All AI agents (Hermes, OpenClaw, Claude Desktop, Cursor) connect via **MCP** (Model Context Protocol).
One tool server, one configuration format, everywhere.

## What it does

Captures the frontmost macOS window in two layers simultaneously:
1. **Visual layer** — High-fidelity PNG screenshot (Retina 2x) via ScreenCaptureKit
2. **Text layer** — Full accessibility text tree via macOS Accessibility API

**Hotkey capture also copies the screenshot PNG to your system clipboard** — press ⌘V in any chat window to paste it instantly.

Everything runs locally — no cloud uploads, no API keys.

## Quick Start

```bash
# 1. Install
chmod +x install.sh && ./install.sh
```

**2. Grant macOS Permissions** (MANDATORY — open both settings pages):

| Permission | Path to add |
|-----------|-------------|
| Screen Recording | System Settings → Privacy → Screen Recording → + → ⌘⇧G → `~/.moly/bin/molyd` |
| Accessibility | System Settings → Privacy → Accessibility → + → ⌘⇧G → `~/.moly/bin/molyd` |

```bash
# 3. Restart daemon after granting permissions
killall molyd; sleep 1; ~/.moly/bin/molyd &
```

**4. Chrome users** (for web page text extraction):  
System Settings → Privacy → Accessibility → + → Google Chrome → toggle ON → ⌘Q + reopen Chrome

```bash
# 5. Verify everything works
cd capture-daemon && make doctor
# → ✅ Daemon running / ✅ AX trusted / ✅ Capture OK

# 6. Configure your agent's MCP (see MCP_SETUP.md)
# 7. Press ⌃⌥⌘Space to capture any window
```

Or manually:

```bash
# 1. Build & install to fixed path
cd capture-daemon && make install

# 2. Start daemon
nohup ~/.moly/bin/molyd > /dev/null 2>&1 &

# 3. Copy MCP server to assets dir
cp moly_mcp.py ~/.moly/
cp SKILL.md ~/.hermes/skills/appshot/   # Hermes
cp SKILL.md ~/.moly/skills/moly/  # Moly

# 4. Add MCP server to your agent config (see MCP_SETUP.md)
```

## Requirements

- macOS 14.0+
- Screen Recording + Accessibility permissions
- Any MCP-compatible AI agent

## Files

| File | Purpose |
|------|---------|
| `moly_mcp.py` | **MCP server** — 6 tools for all agents |
| `SKILL.md` | Agent skill instructions |
| `MCP_SETUP.md` | MCP configuration guide (Hermes, OpenClaw, Claude Desktop, Cursor) |
| `MolyDaemon` | Pre-built daemon binary |
| `install.sh` | One-click installer |
| `notify.js` | Apple-style notification overlay (JXA, white rounded) |
| `flash.js` | Screen flash effect on capture |
| `Moly.png` | Notification icon |
| `capture-hotkey.sh` | Standalone hotkey script (legacy, Shortcuts.app) |

## Agent Configuration (one-time)

**All agents use the same MCP server.** See `MCP_SETUP.md` for detailed config.

```json
// Hermes (config.yaml):
mcp_servers:
  moly:
    command: python3
    args: ["~/.moly/moly_mcp.py"]

// Claude Desktop / Cursor / OpenClaw:
{
  "mcpServers": {
    "moly": {
      "command": "python3",
      "args": ["/path/to/moly_mcp.py"]
    }
  }
}
```

## Token Efficiency

- `get_appshot` returns text-only by default (~2K tokens)
- `get_appshot_image` is a separate tool, only call if text is insufficient
- Server-side image resize at configurable widths
