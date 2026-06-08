---
name: moly
description: |
  IMPORTANT: Do NOT call MCP tools (take_appshot, list_appshots, get_appshot) when user pastes a PNG image or gives a file path. Instead, read the local JSON files directly — this is 100x faster.
  Two capture modes:
  1. Hotkey — user presses ⌃⌥⌘Space, daemon saves to ~/snapshots/
  2. Direct — take_appshot captures frontmost window via MCP
version: 2.0.0
platforms: [macos]
---

# Moly — Screenshot & Accessibility Text Capture

## 🚨 MANDATORY RULES — READ BEFORE ANY ACTION

1. **If user PASTES a PNG image**: Run `python3 ~/.moly/moly_path.py <path_to_pasted_image>` FIRST.
   - If it returns a directory → `cat` the JSON files there. Done.
   - If it returns empty → the image was **re-encoded** (png→jpeg, cache, etc.) and metadata was lost.
     → Run `curl -s 'http://127.0.0.1:19876/snapshots?limit=1'` as fallback.
   - Do NOT loop or retry moly_path.py — it will still be empty on retry.

2. **If user gives a FILE PATH** (e.g. `~/snapshots/.../screenshot.png`): `dirname` it, then `cat $dir/metadata.json` and `cat $dir/accessibility_tree.json`. Done.

3. **ONLY use MCP tools** (`list_appshots`, `get_appshot`) when user says "analyze latest" or "what did I just capture?" and you have NO file path or image.

4. **NEVER**: call `take_appshot` when user already gave you an image. NEVER restart daemon automatically. NEVER wait on process polling.

## ⚡ FAST PATH (Zero API Calls)

Every screenshot PNG contains embedded metadata (`moly_path`) pointing to the local
snapshot directory. Use the `moly_path.py` utility to extract it:

### Pattern A: User provides a file path

If the user gives a path like `~/snapshots/.../screenshot.png`:

```bash
# Read sibling files directly — no API calls needed
SNAP_DIR=$(dirname /path/to/screenshot.png)
cat "$SNAP_DIR/metadata.json"      # instant
cat "$SNAP_DIR/accessibility_tree.json"  # instant
```

### Pattern B: User pastes a PNG image

If the user pastes an image (PNG in clipboard), save it first, then extract:

```bash
# 1. Save pasted image (path depends on how your agent receives attachments)
# 2. Extract the snapshot directory from PNG metadata
SNAP_DIR=$(python3 ~/.moly/moly_path.py /path/to/pasted.png)

# 3. If SNAP_DIR is not empty, read local files directly
if [ -n "$SNAP_DIR" ]; then
    cat "$SNAP_DIR/metadata.json"
    cat "$SNAP_DIR/accessibility_tree.json"
fi
```

The `moly_path.py` script returns the snapshot directory path, or empty string if not found.
This eliminates ALL MCP/HTTP round-trips — reading local files takes milliseconds.

**This eliminates ALL MCP/HTTP round-trips.** Only use the daemon API (MCP tools) when the fast path is unavailable.

## Prerequisites

- macOS 14.0+
- Daemon running on `http://127.0.0.1:19876`
- **One-time permission setup:** `~/.moly/bin/molyd --setup` (interactive wizard)
- Screen Recording + Accessibility permissions granted to **the running daemon binary**
- For Chrome web pages: Google Chrome must also be in Accessibility list + ⌘Q restart
- Hotkey: ⌃⌥⌘Space (built into daemon, no Shortcuts.app needed)

**CRITICAL — macOS TCC permission model:**

Permissions are bound to both **binary path** AND **binary hash** (codesign identity). This means:

1. *Every rebuild* (`make install`) changes the hash → macOS revokes permissions → you MUST re-run `~/.moly/bin/molyd --setup`
2. `AXIsProcessTrusted()` can lie — when daemon runs from Terminal, it **inherits** Terminal.app's Accessibility permission, so it reports `true` even though the daemon binary itself has no TCC entry. The definitive test is a CGEvent tap (which `--setup` uses).
3. When daemon starts via **LaunchAgent** (launchd), it has NO TCC inheritance. The binary must have its OWN Accessibility entry in the TCC database.
4. After granting permissions in System Settings, **restart the daemon** — permissions are only checked at process start.

**Quick check:** `curl -s http://127.0.0.1:19876/axdiag` — `ax_trusted: true` means the HOTKEY works. `ax_test` shows whether a focused window's AX tree is readable.

## How It Works

Captures frontmost window in two layers simultaneously:
1. **Visual** — PNG screenshot (Retina 2x) via ScreenCaptureKit
2. **Text** — Full accessibility tree via macOS Accessibility API

Hotkey capture also copies screenshot PNG to system clipboard (⌘V to paste).**The PNG contains embedded metadata (`moly_path`) pointing to the local snapshot directory.**

## Capture Modes

### Mode 1: Hotkey Capture (Recommended)

Problem: Calling `take_appshot` from agent captures the terminal where the agent runs, not the user's target app.

Solution: User presses hotkey on target app, then asks agent to retrieve.

```
User presses ⌃⌥⌘Space on target app → daemon captures silently
User says "analyze latest screenshot" → list_appshots(limit=1) → get_appshot(id, ...)
```

### Mode 2: Direct API Capture

Only when the target IS the terminal/agent itself:
```bash
curl -X POST http://127.0.0.1:19876/capture
```

## API Reference (daemon at :19876)

**CRITICAL: Only these exact endpoints exist. Do not guess or invent paths.**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Check daemon status |
| `/capture` | POST | Take screenshot now |
| `/snapshots` | GET | **List** all snapshots (use `?limit=1` for latest) |
| `/snapshots/<id>` | GET | **Get detail** (metadata + fullText + axTree) |
| `/screenshots/<id>` | GET | **Get image** (base64 PNG, use `?max_width=600`) |
| `/snapshots/<id>` | DELETE | Delete snapshot |

**Common mistakes to AVOID:**
- ❌ `/appshots` — wrong path
- ❌ `/list` — wrong path  
- ❌ `/api/snapshots` — wrong path
- ✅ `/snapshots?limit=1` — correct path for listing

## Standard Workflow (ALWAYS follow this)

When user says "analyze my screenshot", "look at this", or mentions a recent capture:

**Step 1: List latest snapshot**
```bash
curl -s "http://127.0.0.1:19876/snapshots?limit=1"
```
Response: `{"items":[{"id":"...","appName":"...","windowTitle":"..."}]}`

**Step 2: Get snapshot detail (text first)**
```bash
curl -s "http://127.0.0.1:19876/snapshots/ID_FROM_STEP_1"
```
Response contains: `metadata`, `fullText`, `axTree`

**Step 3: Analyze `fullText`**
If text is sufficient, analyze and respond.

**Step 4 (only if needed): Get image for visual analysis**
```bash
curl -s "http://127.0.0.1:19876/screenshots/ID_FROM_STEP_1?max_width=600"
```

**DO NOT:**
- Try multiple endpoint paths if one fails
- Use `/appshots`, `/list`, or `/api/*` — these do not exist
- Loop or retry the same failing curl command

## Example: Analyze Latest Screenshot

```bash
# 1. Get latest snapshot ID
SNAP=$(curl -s "http://127.0.0.1:19876/snapshots?limit=1" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['items'][0]['id'])")

# 2. Get detail
curl -s "http://127.0.0.1:19876/snapshots/$SNAP" | python3 -c "
import json,sys
data = json.load(sys.stdin)
print('App:', data['metadata']['app']['name'])
print('Window:', data['metadata']['app']['windowTitle'])
print('Text:', data.get('fullText','')[:3000])
"
```

### Get Screenshot Image

```bash
# Get base64 image (resized to 600px width for token efficiency)
curl -s "http://127.0.0.1:19876/snapshots/$SNAP"  # for metadata
curl -s "http://127.0.0.1:19876/screenshots/$SNAP?max_width=600" | python3 -c "
import json,sys
data = json.load(sys.stdin)
print(data.get('imageBase64','')[:100] + '...')
"
```

### Extract Text from Accessibility Tree

When the snapshot's `fullText` is insufficient (e.g., table data, structured content), read the raw accessibility tree:

```bash
curl -s "http://127.0.0.1:19876/snapshots/$SNAP" | python3 -c "
import json,sys
data = json.load(sys.stdin)
ax = data.get('axTree', {})
# Extract all text nodes
def extract(node, texts=[]):
    val = node.get('value', '')
    role = node.get('role', '')
    if role == 'AXStaticText' and val:
        texts.append(val)
    elif role == 'AXLink' and node.get('description'):
        texts.append(f'[LINK:{node[\"description\"]}]')
    for child in node.get('children', []):
        extract(child, texts)
    return texts
for t in extract(ax):
    if len(t) > 2: print(t)
"
```

### Read Snapshot Files Directly

Snapshots are saved locally. Find them via metadata or list:
```bash
# List directories by date
ls /Users/jane/snapshots/

# Each snapshot directory contains:
#   metadata.json, screenshot.png, accessibility_tree.json
```

## Token Budget Guide

| Mode | Approx Tokens | When to Use |
|------|--------------|-------------|
| text-only (fullText) | ~2K | Reading page content, extracting data |
| image @500px | ~70K | UI layout review |
| image @800px | ~155K | Detailed visual inspection |
| full AX tree | ~40K+ | Debugging accessibility, spatial analysis |

Default: text-only. Only request image/AX tree when truly needed.

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Daemon unreachable | Not running or port blocked | `curl http://127.0.0.1:19876/health`; `lsof -i :19876`; `killall molyd; ~/.moly/bin/molyd &` |
| Empty capture / timeout | Screen Recording permission missing | `~/.moly/bin/molyd --setup` (step 2). All three permissions handled automatically now. |
| Hotkey not working | Accessibility permission missing or binary hash changed | `curl http://127.0.0.1:19876/axdiag` → check `ax_trusted`. If false: `~/.moly/bin/molyd --setup` (step 1 auto-grants). |
| **AX tree empty (text=0)** | DAEMON has no Accessibility permission | Run `~/.moly/bin/molyd --setup`. Confirm with `curl http://127.0.0.1:19876/axdiag`. |
| **AX tree only has browser chrome (no web text)** | Chrome's Accessibility bridge not activated | 1) Check `molyd --setup` passes all 3 steps. 2) ⌘Q quit Chrome completely, reopen. 3) Chrome's AX bridge only exposes web content when the page uses semantic HTML/ARIA. **Modern SPAs (React/Vue) may not expose their dynamic content to macOS AX API at all.** |
| **Web page content missing even with all permissions OK** | Page is a JS-heavy SPA (B站, YouTube, Twitter, etc.) | **Known limitation:** Chrome/macOS AX API cannot extract dynamically rendered React/Vue component trees. Workarounds: (a) Use Safari instead — Safari has better AX integration, (b) Use the page's public API (B站 API, YouTube API), (c) Use `include_image=true` for visual analysis. **Do NOT retry — this is not a permission issue.** |
| API returns 404 | Wrong endpoint path | Use `/snapshots`, not `/appshots` or `/list` |
| `ax_trusted: true` but hotkey still doesn't work | Daemon started BEFORE permissions were granted | Restart daemon: `killall molyd; ~/.moly/bin/molyd &` |
