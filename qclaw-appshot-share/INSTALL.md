# QClaw Appshot — Installation Guide

This guide is designed to be followed by either a human or an AI agent (Hermes/Claude).

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode Command Line Tools: `xcode-select --install`
- Hermes Agent installed

## Step 1: Build & Start the Daemon

```bash
# Clone or copy the capture-daemon repository
cd /path/to/capture-daemon

# Build (Swift Package Manager)
swift build

# Run in background
./.build/debug/QClawDaemon &
```

The daemon listens on `http://127.0.0.1:19876`.

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
cp appshot.py ~/.hermes/tools/

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
| **AX tree empty (text_length=0)** | **Accessibility permission not granted to `~/.qclaw-appshot/bin/qclawd`** | **Re-do Step 2 (Accessibility). This is the #1 cause.** |
| Tools not appearing in Hermes | appshot.py not in correct path | `cp appshot.py ~/.hermes/hermes-agent/tools/` |
| Web page text missing | Chrome AX Tree limitation | Normal — Web content is not exposed to macOS Accessibility API. Use screenshot image for visual analysis instead. |
