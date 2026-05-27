# QClaw Appshot — macOS Screenshot + Accessibility Text Capture

Shareable plugin package for Hermes Agent.

## What it does

Captures the frontmost macOS window in two layers simultaneously:
1. **Visual layer** — High-fidelity PNG screenshot (Retina 2x) via ScreenCaptureKit
2. **Text layer** — Full accessibility text tree via macOS Accessibility API

**Hotkey capture also copies the screenshot PNG to your system clipboard** — press ⌘V in any chat window to paste it instantly.

Everything runs locally — no cloud uploads, no API keys.

## Quick Start

```bash
# One-line install
chmod +x install.sh && ./install.sh

# Then grant permissions when prompted:
#   System Settings → Privacy & Security → Screen Recording → Enable QClawDaemon
#   System Settings → Privacy & Security → Accessibility → Enable QClawDaemon

# Press ⌃⌥⌘Space to capture any window. Screenshot auto-copied to clipboard.
```

Or manually:

```bash
# 1. Build & start the daemon
cd capture-daemon && make build && make run &

# 2. Test it
curl -X POST http://127.0.0.1:19876/capture

# 3. Install Hermes plugin
cp appshot.py ~/.hermes/tools/
cp SKILL.md ~/.hermes/skills/appshot/

# 4. Press ⌃⌥⌘Space (daemon listens natively — no Shortcuts.app needed)
```

## Requirements

- macOS 14.0+
- Screen Recording permission (System Settings → Privacy)
- Accessibility permission (System Settings → Privacy)
- Hermes Agent (for AI integration)

## Files

| File | Purpose |
|------|---------|
| `appshot.py` | Hermes tool registrations (5 tools) |
| `SKILL.md` | Agent skill instructions |
| `capture-hotkey.sh` | PID-aware hotkey script + auto clipboard copy |
| `notify.js` | Apple-style notification overlay (JXA, white rounded) |
| `INSTALL.md` | Detailed installation guide |

## Token Efficiency

The tools are optimized for minimal token consumption:
- `get_appshot` returns text-only by default (~2K tokens)
- Image and AX tree are opt-in via `include_image` / `include_ax_tree`
- Server-side image resize at configurable widths (400-800px)
