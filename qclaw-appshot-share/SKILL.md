---
name: appshot
description: |
  macOS screenshot + accessibility text capture for any window.
  Two capture modes:
  1. Hotkey (recommended) — user presses shortcut on target window, daemon captures, agent queries via list_appshots/get_appshot
  2. Direct call — take_appshot captures current frontmost window
  Use when user says "analyze this", "what's on my screen", "check this error", "look at latest screenshot", etc.
version: 1.5.0
platforms: [macos]
metadata:
  hermes:
    tags: [screenshot, capture, appshot, desktop, macos, vision]
    category: desktop
---

# Appshot — Screenshot & Window Context

## Core Concept: Hotkey vs Direct Call

### Problem: Why does take_appshot capture Terminal?

When you call `take_appshot` through Hermes, Hermes runs inside Terminal, so Terminal IS the "frontmost window". You'll capture Terminal instead of Chrome/Figma/IDE.

### Solution: Hotkey First, Query Later

```
User action (in target window)      Hermes (in conversation)
─────────────────────────────      ─────────────────────────
1. Press ⌃⌥⌘Space on target app    (daemon captures silently)
   ↳ Screenshot PNG auto-copied to clipboard
2. Switch back to Hermes
3. "Analyze latest screenshot"     → list_appshots(limit=1)
                                   → get_appshot(id, include_image=true)
                                   → Returns analysis
```

**Tip:** The hotkey also copies the screenshot PNG to your system clipboard. You can paste it (⌘V) directly into any chat window without needing `get_appshot(include_image=true)`.

## Available Tools

| Tool | Purpose | Key Parameters |
|------|---------|---------------|
| `take_appshot` | Capture current frontmost window | None (optional: pid) |
| `list_appshots` | Browse capture history, get latest | app_name, date_from, date_to, limit, offset |
| `get_appshot` | Full detail of one snapshot | snapshot_id (required), include_image, include_ax_tree, image_max_width |
| `search_appshots` | Search by keyword | query (required), search_in |
| `delete_appshot` | Delete a snapshot | snapshot_id (required) |

## When to Use Each Tool

### list_appshots + get_appshot (Most Common)

Use when user says:
- "Analyze my latest screenshot" / "What did I just capture?"
- "Look at this page" (user already pressed hotkey on target app)
- "Compare my last two screenshots"

**Flow:**
1. `list_appshots(limit=1)` → get latest snapshot ID
2. Check `appName` matches what user describes
3. `get_appshot(id, include_image=true)` → get text + image
4. Analyze based on `full_text`; use `image_base64` for visual details

### take_appshot (Specific Cases)

Only when the target IS Hermes/Terminal itself:
- User wants you to see terminal output
- User pasted code and wants context of the full window

### search_appshots

- "Find my Figma screenshots from last week"
- "Search captures containing 'error'"

## get_appshot Token Budget

| Mode | Tokens | When |
|------|--------|------|
| text-only (default) | ~2K | Most analysis tasks — reading text, extracting data |
| image @500px | ~70K | Layout analysis, UI review |
| image @800px | ~155K | Detailed visual inspection |
| + AX tree | +40K | Debugging accessibility, spatial analysis |

**Default:** `include_image=False`, `include_ax_tree=False`. Only request what you need.

## Usage Patterns

### Pattern 1: Hotkey → Query (Primary)

```
User presses hotkey on target → screenshot saved to daemon
User says "analyze latest screenshot"
→ list_appshots(limit=1)
→ get_appshot(id, include_image=true)
→ Analyze and respond
```

### Pattern 2: Cross-App Comparison

```
User captures Chrome, Figma, VS Code in sequence
User says "compare my last 3 screenshots"
→ list_appshots(limit=3)
→ get_appshot for each as needed
→ Compare and analyze
```

### Pattern 3: Text Extraction (No Image)

```
User captures a web page / document
User says "extract all comments with authors"
→ list_appshots(limit=1)
→ get_appshot(id)  # text-only, no image needed
→ Parse full_text and extract requested data
```

## Fallback

If tools are unavailable (daemon not running, permissions missing), use:

```bash
# Screenshot only
screencapture -w /tmp/window.png

# Get frontmost app info
osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'
```

## Requirements

- macOS 14.0+
- Capture daemon running on port 19876 (`curl http://127.0.0.1:19876/health`)
- **Screen Recording + Accessibility permissions** (see Setup below)
- **No Shortcuts.app needed** — hotkey (⌃⌥⌘Space) is built into the daemon

## First-Time Setup (CRITICAL)

When installing appshot for the first time, the user MUST grant two macOS permissions.
**Guide the user through this step-by-step. Do not skip.**

### Step 1: Install the daemon
```bash
cd qclaw-appshot-share
chmod +x install.sh && ./install.sh
```

### Step 2: Grant Screen Recording permission
1. System Settings → Privacy & Security → Screen Recording
2. Click **+** → press ⌘⇧G → enter `~/.qclaw-appshot/bin/qclawd` → Add
3. Toggle the switch ON (blue)

### Step 3: Grant Accessibility permission
1. System Settings → Privacy & Security → Accessibility
2. Click **+** → press ⌘⇧G → enter `~/.qclaw-appshot/bin/qclawd` → Add
3. Toggle the switch ON (blue)

### Step 4: Restart the daemon
```bash
killall qclawd; sleep 1; ~/.qclaw-appshot/bin/qclawd &
```

### Step 5: Verify
```bash
curl http://127.0.0.1:19876/health
# → {"status":"ok"}
```

**Test the hotkey**: Press ⌃⌥⌘Space on any window. You should see a screen flash.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| AX tree empty (text_length=0) | Accessibility permission missing for `~/.qclaw-appshot/bin/qclawd` | Re-check Step 3 above |
| Capture timeout / no screenshot | Screen Recording permission missing | Re-check Step 2 above |
| "Address already in use" | Old daemon still running | `killall qclawd` then restart |
| Hotkey not working | Accessibility permission missing | Re-check Step 3 above |
