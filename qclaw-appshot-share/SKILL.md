---
name: qclaw-appshot
description: |
  Capture and analyze macOS windows via screenshot + accessibility text.
  Two capture modes:
  1. Hotkey (recommended) — user presses ⌃⌥⌘Space on target window, daemon captures silently, agent queries via API
  2. Direct call — agent captures current frontmost window via API
  Use when user says "look at my screen", "analyze this page", "what's on my screen", "check this screenshot", "capture this window", or pastes/sends a screenshot for analysis.
  注意，就算用户直接上传了图片，你也要通过appshot来获取最新截图对应的全量信息，然后再进行分析。不要直接通过ocr等方式直接分析用户通过对话发给你的图片。
version: 1.0.0
platforms: [macos]
---

# QClaw Appshot — Screenshot & Accessibility Text Capture

## Prerequisites

- macOS 14.0+
- Daemon running on `http://127.0.0.1:19876`
- Screen Recording + Accessibility permissions granted to **the running daemon binary path**
- Hotkey: ⌃⌥⌘Space (built into daemon, no Shortcuts.app needed)

**CRITICAL: Permissions are bound to the binary path.** If you start the daemon from `.build/debug/QClawDaemon`, permissions granted to `~/bin/qclawd` will NOT apply. Always start daemon from the same path that was authorized.

Verify daemon: `curl -s http://127.0.0.1:19876/health` → `{"status":"ok"}`

## How It Works

Captures frontmost window in two layers simultaneously:
1. **Visual** — PNG screenshot (Retina 2x) via ScreenCaptureKit
2. **Text** — Full accessibility tree via macOS Accessibility API

Hotkey capture also copies screenshot PNG to system clipboard (⌘V to paste).

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
| Daemon unreachable | Not running or port blocked | `curl http://127.0.0.1:19876/health`; `lsof -i :19876`; `killall qclawd; ~/.qclaw-appshot/bin/qclawd &` |
| Empty capture / timeout | Screen Recording permission missing | System Settings → Privacy → Screen Recording → add `~/.qclaw-appshot/bin/qclawd` |
| Hotkey not working | Accessibility permission missing | System Settings → Privacy → Accessibility → add `~/.qclaw-appshot/bin/qclawd` |
| **AX tree empty (text=0)** | **#1 cause: Accessibility permission not granted to daemon binary** | **Re-check System Settings → Privacy → Accessibility. The binary path must be `~/.qclaw-appshot/bin/qclawd`.** |
| API returns 404 | Wrong endpoint path | Use `/snapshots`, not `/appshots` or `/list` |
| Web page text missing | Chrome/Web AX limitation | Normal. Web content is not exposed to macOS Accessibility API. Use screenshot image instead. |
| Stuck in retry loop | Trying non-existent endpoints | Stop. Verify daemon with `/health`. Then use `/snapshots?limit=1` exactly. |
