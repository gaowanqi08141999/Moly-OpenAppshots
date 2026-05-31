# QClaw Appshot — Installation Guide

This guide is designed to be followed by either a human or an AI agent (Hermes/Claude).

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode Command Line Tools: `xcode-select --install`
- Hermes Agent installed

## Step 1: Build & Install the Daemon

```bash
# Option A: One-step install (recommended)
cd /path/to/capture-daemon
make install          # builds + copies to ~/.qclaw-appshot/bin/qclawd

# Option B: Manual build + copy
cd /path/to/capture-daemon
swift build
mkdir -p ~/.qclaw-appshot/bin
cp .build/debug/QClawDaemon ~/.qclaw-appshot/bin/qclawd
```

Start the daemon (always use this path):
```bash
nohup ~/.qclaw-appshot/bin/qclawd > /dev/null 2>&1 &
```

The daemon listens on `http://127.0.0.1:19876`.

> ⚠️ **CRITICAL**: Always use `~/.qclaw-appshot/bin/qclawd`. macOS authorizes permissions by binary path. If you run `.build/debug/QClawDaemon` directly, permissions will not apply and AX tree will be empty.
>
> The daemon has a **path guard**: if started from the wrong path, it prints a bold warning box telling you exactly how to fix it.

## Step 2: Grant macOS Permissions (MANDATORY)

macOS requires manual authorization for two permissions. The daemon will NOT work without them.

**Screen Recording** (needed for screenshot capture):
1. System Settings → Privacy & Security → Screen Recording
2. Click **+** → press **⌘⇧G** → enter `~/.qclaw-appshot/bin/qclawd` → Open
3. Toggle the switch **ON** (blue)

**Accessibility** (needed for text extraction + hotkey):
1. System Settings → Privacy & Security → Accessibility
2. Click **+** → press **⌘⇧G** → enter `~/.qclaw-appshot/bin/qclawd` → Open
3. Toggle the switch **ON** (blue)

**Restart the daemon after granting permissions:**
```bash
killall qclawd; sleep 1; ~/.qclaw-appshot/bin/qclawd &
```

## Step 3: Install the Hermes Plugin

```bash
# Copy tool registrations
cp appshot.py ~/.hermes/hermes-agent/tools/

# Copy skill instructions
mkdir -p ~/.hermes/skills/appshot/
cp SKILL.md ~/.hermes/skills/appshot/
```

Restart Hermes after installation. Verify with: `/skills` should show `appshot`.

## Step 4: Verify

The daemon listens for **⌃⌥⌘Space** natively — no Shortcuts.app configuration needed.

```bash
# Check daemon health
curl http://127.0.0.1:19876/health
# → {"status":"ok"}

# Test capture via API
curl -X POST http://127.0.0.1:19876/capture
# → {"id":"...", "appName":"...", ...}

# Test hotkey: switch to any app, press ⌃⌥⌘Space
# → A white rounded notification appears at top-right
# → The screenshot PNG is copied to clipboard (paste with ⌘V)
```

## Step 5: Test in Hermes

```bash
# Check daemon health
curl http://127.0.0.1:19876/health
# → {"status":"ok"}

# Test capture
curl -X POST http://127.0.0.1:19876/capture
# → {"id":"...", "appName":"...", ...}

# Test hotkey: switch to any app, press ⌃⌥⌘Space
# → A white rounded notification appears at top-right
# → The screenshot PNG is copied to clipboard (paste with ⌘V)
```

## Step 6: Test in Hermes

In Hermes, say: "Take an appshot" or press the hotkey, then:
- "List my latest screenshots"
- "Analyze my latest screenshot"

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Daemon won't start | Port 19876 in use | `lsof -i :19876` then `killall qclawd` |
| Capture returns empty / timeout | Screen Recording permission missing | Re-do Step 2 (Screen Recording) |
| Hotkey not working | Accessibility permission missing | Re-do Step 2 (Accessibility) |
| **AX tree empty (text_length=0)** | **#1 cause: Running `.build/debug/QClawDaemon` directly. macOS permissions are bound to the binary path.** | **Kill daemon, then always start with `~/.qclaw-appshot/bin/qclawd`. Re-check System Settings → Accessibility that `~/.qclaw-appshot/bin/qclawd` is enabled.** |
| AX tree empty (still) | Multiple daemon paths in Accessibility list, wrong one active | Remove ALL QClawDaemon entries from Accessibility, add ONLY `~/.qclaw-appshot/bin/qclawd`, restart daemon |
| Tools not appearing in Hermes | appshot.py not in correct path or toolset not enabled | `cp appshot.py ~/.hermes/hermes-agent/tools/` and add `appshot` to `toolsets` in `~/.hermes/config.yaml` |
| Web page text missing | Chrome AX Tree limitation | Normal — Web content is not exposed to macOS Accessibility API. Use screenshot image for visual analysis instead. |
