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

## Step 2: Grant macOS Permissions

**Screen Recording:**
- System Settings → Privacy & Security → Screen Recording
- Enable the terminal app that runs the daemon
- (Or enable QClawDaemon if it appears)

**Accessibility:**
- System Settings → Privacy & Security → Accessibility
- Enable the terminal app that runs the daemon

Restart the daemon after granting permissions.

## Step 3: Install the Hermes Plugin

```bash
# Copy tool registrations
cp appshot.py ~/.hermes/tools/

# Copy skill instructions
mkdir -p ~/.hermes/skills/appshot/
cp SKILL.md ~/.hermes/skills/appshot/
```

Restart Hermes after installation. Verify with: `/skills` should show `appshot`.

## Step 4: Set Up the Keyboard Shortcut

1. Open **Shortcuts.app**
2. Create a new shortcut, name it "Capture Appshot"
3. Add a **"Run Shell Script"** action
4. Set shell to `/bin/bash`, Pass Input: "to stdin"
5. Paste: `bash /path/to/qclaw-appshot-share/capture-hotkey.sh`
6. Click the (i) info button → "Use as Quick Action" → "Add Keyboard Shortcut"
7. Set shortcut to **⌃⌥⌘Space** (or your preference)
8. Under "Services" select **no input** and **any application**

## Step 5: Verify

```bash
# Check daemon health
curl http://127.0.0.1:19876/health
# → {"status":"ok"}

# Test capture
curl -X POST http://127.0.0.1:19876/capture
# → {"id":"...", "appName":"...", ...}

# Test hotkey: switch to any app, press ⌃⌥⌘Space
# → A frosted-glass notification should appear at top-right
```

## Step 6: Test in Hermes

In Hermes, say: "Take an appshot" or press the hotkey, then:
- "List my latest screenshots"
- "Analyze my latest screenshot"

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Daemon won't start | Check port 19876 isn't in use: `lsof -i :19876` |
| Capture returns empty | Check Screen Recording & Accessibility permissions |
| Hotkey captures wrong app | Ensure Shortcuts "Pass Input" is "to stdin" |
| Tools not appearing | Check appshot.py is in `~/.hermes/tools/`, restart Hermes |
| AX tree is empty | The app may not support Accessibility API |
