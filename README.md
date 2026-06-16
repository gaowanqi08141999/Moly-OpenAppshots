<img src="https://raw.githubusercontent.com/gaowanqi08141999/Moly-OpenAppshots/main/cover.png" style="display:none">

# Moly — Open Appshots for AI Agents

[English](README.md) | [中文](README_CN.md)

> *Hey, human! C’mon, let me sneak a peek at your screen🐱*

**Moly** captures your macOS screen — screenshot + accessibility text tree — and feeds the result to any AI agent through a standard MCP (Model Context Protocol) interface.

### What Moly does

- **One hotkey (⌃⌥⌘Space)** captures the frontmost window in two layers simultaneously
- **Screenshot**: High-fidelity Retina 2x PNG via macOS ScreenCaptureKit
- **Text tree**: Full accessibility tree via macOS Accessibility API — your agent reads every label, button, and paragraph on screen
- **Instant clipboard**: The PNG is automatically copied to your clipboard for ⌘V paste
- **Fast agent lookup**: Every capture writes `~/.moly/latest.txt` with the snapshot directory path. Agent does `cat ~/.moly/latest.txt` → reads local JSON — zero HTTP round-trips

### How it works

1. A lightweight Swift daemon (`~/.moly/bin/molyd`) runs locally on port 19876
2. It listens for the ⌃⌥⌘Space hotkey globally via a CGEvent tap
3. On capture, it gets the frontmost window's PID, snaps a screenshot (ScreenCaptureKit), and traverses the window's accessibility element tree
4. Both are saved to `~/snapshots/<date>/<id>/` with a SQLite index
5. `~/.moly/latest.txt` is atomically updated with the snapshot directory path — this is the primary agent lookup path (one `cat`, zero API calls)
6. The PNG is also embedded with `moly_path` metadata as a secondary lookup path, then copied to the clipboard
7. A Python MCP server (`moly_mcp.py`) exposes 6 tools via stdio JSON-RPC — any MCP-compatible agent can call them as a fallback

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![MCP](https://img.shields.io/badge/MCP-compatible-purple)](https://modelcontextprotocol.io/)

## Architecture Diagram

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
  (6 tools)    metadata directly
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
- **Agent fast path** — `~/.moly/latest.txt` gives agents the snapshot directory in one `cat`; zero API calls
- **PNG metadata embedding** — secondary lookup: PNG `tEXt` chunk carries `moly_path` for direct-to-disk access (works when the image is not re-encoded)
- **Electron app support** — `--setup` auto-configures Longbridge Pro, VS Code, Discord, Slack, and other Electron desktop apps
- **Unified MCP** — same 6 tools for Hermes, OpenClaw, Claude Desktop, Cursor, and any MCP client
- **Apple-style notification** — white rounded overlay at top-right with custom icon
- **Screen flash** — instant visual feedback on capture
- **100% local** — no cloud uploads, no API keys, no network required

## Quick Start

```bash
# 1. Download and install
git clone https://github.com/gaowanqi08141999/Moly-OpenAppshots.git
cd moly/moly-share
chmod +x install.sh && ./install.sh

# 2. Run the one-time permission setup wizard
~/.moly/bin/molyd --setup
#    → Auto-configures all permissions — no manual System Settings clicking
#    → Handles: Accessibility (molyd), Screen Recording (molyd),
#               Accessibility (Google Chrome), Accessibility (Electron apps)

# 3. Restart Chrome / Electron apps (if you use them)
#    Launch with: open -a "App Name" --args --force-renderer-accessibility
#    This flag is REQUIRED for Chrome/Electron to expose web content to AX

# 4. Restart daemon (required after granting new permissions)
killall molyd; sleep 1; ~/.moly/bin/molyd &

# 5. Verify
cd ../capture-daemon && make doctor
# → ✅ Daemon running / ✅ AX trusted / ✅ Capture OK

# 6. Configure your agent's MCP server (one-time, see below)

# 7. Ready! Press ⌃⌥⌘Space on any window, paste (⌘V) to your agent

# 💡 If you ever rebuild or update the binary, re-run:
#    ~/.moly/bin/molyd --setup
#    (macOS TCC binds permissions to binary hash — every rebuild invalidates old grants.)
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

### Chrome & Electron App Users

Chrome and Electron apps (VS Code, Discord, Slack, Longbridge Pro, etc.) render web content in sub-processes. Their AX bridge only activates when **the app itself** has Accessibility permission AND is launched with `--force-renderer-accessibility`.

`molyd --setup` handles this automatically (steps 3 & 4). After setup:

- ⌘Q quit and reopen each app with: `open -a "App Name" --args --force-renderer-accessibility`
- Verify: `curl -s http://127.0.0.1:19876/axdiag` → `ax_trusted: true`

## Tools

| Tool | What it does | When to use |
|------|-------------|-------------|
| `take_appshot` | Capture current frontmost window | "Screenshot my terminal" |
| `list_appshots` | Browse snapshot history | "Show me recent captures" |
| `get_appshot` | Get text + metadata (~2K tokens) | "What's on this page?" |
| `get_appshot_image` | Get screenshot image (~70K tokens) | "Analyze this layout visually" |
| `search_appshots` | Search by keyword | "Find my Spotify screenshots" |
| `delete_appshot` | Delete a snapshot | Cleanup |

> 💡 **The fastest path is no API call at all.** When a user pastes an image, agents read `~/.moly/latest.txt` → `cat` the local JSON files. This is 100x faster than MCP and works offline.

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
Chrome's multi-process architecture isolates the web content AX tree from the main process. Granting Accessibility permission to Chrome itself enables the bridge. Same applies to all Electron-based desktop apps (VS Code, Discord, Slack, etc.) — `molyd --setup` auto-configures them.

**Does it work with finance/stock apps (Longbridge Pro, etc.)?**  
Yes. Electron-based desktop apps are auto-detected and configured by `molyd --setup` (step 4). After configuration, launch the app with `open -a "App Name" --args --force-renderer-accessibility`. Non-Electron custom-rendering apps may not expose AX trees.

**How do agents find the snapshot data?**  
Primary path: `cat ~/.moly/latest.txt` returns the latest snapshot directory instantly — one local `cat`, zero HTTP. Secondary: `python3 ~/.moly/moly_path.py <image>` reads embedded PNG metadata. Fallback: `curl http://127.0.0.1:19876/snapshots?limit=1` via daemon API.

**Where are snapshots stored?**  
`~/snapshots/<date>/<id>/` — each snapshot has `screenshot.png`, `metadata.json`, and `accessibility_tree.json`. The PNG file embeds the directory path in its metadata for instant agent access.

**Can I change the hotkey?**  
Currently ⌃⌥⌘Space is hardcoded. See `HotkeyListener.swift` to customize.

## License

MIT — see [LICENSE](LICENSE).

<p align="center">
  <sub>Made with 🐾 by the Moly team</sub>
</p>
