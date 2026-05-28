# QClaw Appshot — macOS Screenshot + Accessibility Text Capture

Shareable plugin package for Hermes Agent, OpenClaw, Claude Desktop, Cursor, or any MCP client.

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

# 2. Grant permissions (MANDATORY — macOS will not prompt automatically)
#    System Settings → Privacy & Security → Screen Recording
#      → + → ⌘⇧G → ~/.qclaw-appshot/bin/qclawd → toggle ON
#    System Settings → Privacy & Security → Accessibility
#      → + → ⌘⇧G → ~/.qclaw-appshot/bin/qclawd → toggle ON
#
#    ⚠️  Always use this exact path. Permissions are bound to the binary.
#       Do NOT run .build/debug/QClawDaemon directly.

# 3. Restart daemon
killall qclawd; sleep 1; ~/.qclaw-appshot/bin/qclawd &

# 4. Press ⌃⌥⌘Space to capture any window. Screenshot auto-copied to clipboard.
```

Or manually:

```bash
# 1. Build daemon
cd capture-daemon && make build

# 2. Copy to fixed path (permissions stick to this path)
mkdir -p ~/.qclaw-appshot/bin
cp .build/debug/QClawDaemon ~/.qclaw-appshot/bin/qclawd

# 3. Start daemon (always use this path)
nohup ~/.qclaw-appshot/bin/qclawd > /dev/null 2>&1 &

# 4. Test it
curl -X POST http://127.0.0.1:19876/capture

# 5. Install Hermes plugin
cp appshot.py ~/.hermes/hermes-agent/tools/
mkdir -p ~/.hermes/skills/appshot/
cp SKILL.md ~/.hermes/skills/appshot/

# 6. Press ⌃⌥⌘Space (daemon listens natively — no Shortcuts.app needed)
```

## Requirements

- macOS 14.0+
- Screen Recording permission (System Settings → Privacy)
- Accessibility permission (System Settings → Privacy)
- Hermes Agent (for AI integration) or any MCP-compatible client

## Files

| File | Purpose |
|------|---------|
| `appshot.py` | Hermes tool registrations (5 tools) |
| `SKILL.md` | Agent skill instructions |
| `capture-hotkey.sh` | Standalone hotkey script (legacy, Shortcuts.app) |
| `appshot_mcp.py` | MCP server for OpenClaw / Claude Desktop / Cursor |
| `MCP_SETUP.md` | MCP configuration guide |
| `notify.js` | Apple-style notification overlay (JXA, white rounded) |
| `INSTALL.md` | Detailed installation guide |

## Token Efficiency

The tools are optimized for minimal token consumption:
- `get_appshot` returns text-only by default (~2K tokens)
- Image and AX tree are opt-in via `include_image` / `include_ax_tree`
- Server-side image resize at configurable widths (400-800px)
