<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/<user>/moly/main/Moly.png">
  <img src="https://raw.githubusercontent.com/<user>/moly/main/Moly.png" alt="Moly" width="120" align="right">
</picture>

# Moly — Open Appshots for AI Agents

[English](README.md) | [中文](README_CN.md)

> *A tiny mole that sees your screen and tells AI agents what's there.*

Moly captures your macOS screen — screenshot + accessibility text — and feeds it to any AI agent through a standard MCP (Model Context Protocol) interface. Press a hotkey, paste the image, and your agent reads everything on your screen in milliseconds.

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![MCP](https://img.shields.io/badge/MCP-compatible-purple)](https://modelcontextprotocol.io/)

## How it works

```
You press ⌃⌥⌘Space
        │
        ▼
┌──────────────────┐
│  ScreenCaptureKit │  →  Retina 2x PNG screenshot
│  Accessibility API│  →  Structured text tree (AX)
└────────┬─────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
 ~/snapshots/   Clipboard (PNG + embedded metadata)
    │              │
    ▼              ▼
  MCP server    Agent parses
  (5 tools)    metadata directly
    │              │
    └──────┬───────┘
           ▼
     AI Agent analyzes everything
```

**One hotkey. PNG in clipboard. Text tree on disk. Agent reads them both.**

## Features

- **⌃⌥⌘Space hotkey** — built into the daemon, no Shortcuts.app needed
- **Dual capture** — Retina PNG screenshot + full AX text tree in one shot
- **Clipboard auto-copy** — paste directly into any chat window
- **PNG metadata embedding** — pasted images carry the file path; agents read local files in milliseconds (no API calls)
- **Unified MCP** — same 5 tools for Hermes, OpenClaw, Claude Desktop, Cursor, and any MCP client
- **Apple-style notification** — white rounded overlay at top-right with custom icon
- **Screen flash** — instant visual feedback on capture
- **100% local** — no cloud uploads, no API keys, no network required

## Quick Start

```bash
# 1. Download and install
git clone https://github.com/<user>/moly.git
cd moly/moly-share
chmod +x install.sh && ./install.sh

# 2. Grant permissions (mandatory, one-time)
#    System Settings → Privacy & Security
#    → Screen Recording  → + → ⌘⇧G → ~/.moly/bin/molyd
#    → Accessibility     → + → ⌘⇧G → ~/.moly/bin/molyd

# 3. Restart daemon
killall molyd; sleep 1; ~/.moly/bin/molyd &

# 4. Verify
cd ../capture-daemon && make doctor
# → ✅ Daemon running / ✅ AX trusted / ✅ Capture OK

# 5. Configure your agent's MCP server (one-time, see below)

# 6. Ready! Press ⌃⌥⌘Space on any window, paste (⌘V) to your agent
```

### Agent Configuration

**All agents share one MCP server.** Add this to your agent's config:

```yaml
# Hermes: ~/.hermes/config.yaml
mcp_servers:
  moly:
    command: python3
    args: ["~/.moly/moly_mcp.py"]
```

```json
// Claude Desktop: ~/Library/Application Support/Claude/claude_desktop_config.json
// OpenClaw: ~/.openclaw/openclaw.json
// Cursor: Settings → MCP
{
  "mcpServers": {
    "moly": {
      "command": "python3",
      "args": ["/path/to/moly_mcp.py"]
    }
  }
}
```

See [MCP_SETUP.md](moly-share/MCP_SETUP.md) for all platforms.

### Chrome Users

For web page text extraction, Chrome needs Accessibility permission too:

- System Settings → Privacy → Accessibility → **+** → Google Chrome → toggle ON
- ⌘Q quit Chrome and reopen (required to activate the AX bridge)

## Tools

| Tool | What it does | When to use |
|------|-------------|-------------|
| `take_appshot` | Capture current frontmost window | "Screenshot my terminal" |
| `list_appshots` | Browse snapshot history | "Show me recent captures" |
| `get_appshot` | Get text + metadata (~2K tokens) | "What's on this page?" |
| `get_appshot_image` | Get screenshot image (~70K tokens) | "Analyze this layout visually" |
| `search_appshots` | Search by keyword | "Find my Spotify screenshots" |
| `delete_appshot` | Delete a snapshot | Cleanup |

## Architecture

```
┌──────────────────────────────────────┐
│          MolyDaemon (:19876)          │
│  Swift, ScreenCaptureKit + AX API    │
│                                      │
│  Hotkey: ⌃⌥⌘Space                   │
│  Storage: ~/snapshots/ (SQLite+FS)   │
│  Assets: ~/.moly/ (icon, notify, etc)│
└──────────────┬───────────────────────┘
               │ HTTP
    ┌──────────┴──────────┐
    ▼                     ▼
  moly_mcp.py        Direct calls
  (MCP stdio)        (curl, Python, etc)
    │
 ┌──┴──────────────────────┐
 ▼        ▼        ▼       ▼
Hermes  OpenClaw Cursor  Claude
```

## Project Structure

```
moly/
├── capture-daemon/              # Swift source
│   ├── Sources/
│   │   ├── MolyDaemon/          # main.swift, CaptureEngine.swift, ...
│   │   └── MolyNotify/          # notify.js, flash.js
│   ├── Package.swift
│   ├── Makefile
│   └── doctor.py
├── moly-share/                  # Distribution package
│   ├── molyd                    # Pre-built binary
│   ├── install.sh               # One-click installer
│   ├── moly_mcp.py              # MCP server (all agents)
│   ├── moly_path.py             # PNG metadata extractor
│   ├── notify.js / flash.js     # UX assets
│   ├── Moly.png / SKILL.md      # Icon & agent instructions
│   └── README.md / INSTALL.md   # Docs
├── LICENSE (MIT)
└── README.md                    # ← You are here
```

## Building from Source

Requires Xcode Command Line Tools (`xcode-select --install`):

```bash
cd capture-daemon
make install     # builds + copies to ~/.moly/bin/molyd
make doctor      # verify everything works
```

## FAQ

**Why not use macOS's built-in screenshot tools?**  
`Cmd-Shift-4` captures pixels only. Moly captures both pixels *and* the accessibility text tree — your agent can read what's on screen, not just look at it.

**Does it work offline?**  
Yes. Everything runs locally. No network required.

**Why does Chrome need extra permission?**  
Chrome's multi-process architecture isolates the web content AX tree from the main process. Granting Accessibility permission to Chrome itself enables the bridge.

**Where are snapshots stored?**  
`~/snapshots/<date>/<id>/` — each snapshot has `screenshot.png`, `metadata.json`, and `accessibility_tree.json`. The PNG file embeds the directory path in its metadata for instant agent access.

**Can I change the hotkey?**  
Currently ⌃⌥⌘Space is hardcoded. See `HotkeyListener.swift` to customize.

## License

MIT — see [LICENSE](LICENSE).

<p align="center">
  <sub>Made with 🐾 by the Moly team</sub>
</p>
