#!/bin/bash
# QClaw Appshot — Hotkey Capture Script
# Captures the CURRENT frontmost window (whatever the user is looking at),
# even when the shortcut runner briefly steals focus.
#
# The key trick: we grab the frontmost app's PID BEFORE anything else runs,
# then tell the daemon to capture THAT app specifically, ignoring whatever
# happens to be frontmost by the time the HTTP request arrives.

DAEMON_URL="${QCLAW_DAEMON_URL:-http://127.0.0.1:19876}"

# Step 1: Get the REAL frontmost app's PID — BEFORE any focus change
# System Events query is read-only and won't steal focus
FRONTMOST_PID=$(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true' 2>/dev/null)

if [ -z "$FRONTMOST_PID" ]; then
    osascript -e 'display notification "Cannot determine frontmost app" with title "Appshot Error"' 2>/dev/null
    exit 1
fi

# Step 2: Tell daemon to capture THAT specific app
RESPONSE=$(curl -s -X POST "${DAEMON_URL}/capture?pid=${FRONTMOST_PID}" 2>&1)

if [ $? -ne 0 ]; then
    osascript -e "display notification \"Daemon not reachable on ${DAEMON_URL}\" with title \"Appshot Error\"" 2>/dev/null
    exit 1
fi

# Step 3: Parse result
APP_NAME=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('appName','?'))" 2>/dev/null)
TITLE=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('windowTitle','')[:60])" 2>/dev/null)
TEXT_LEN=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('textLength',0))" 2>/dev/null)
SNAP_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)

if [ -z "$APP_NAME" ] || [ "$APP_NAME" = "?" ]; then
    osascript -e 'display notification "Capture failed — check daemon logs" with title "Appshot Error"' 2>/dev/null
    exit 1
fi

# Step 4: Show dialog — auto-dismiss after 2 seconds, or click OK
# Escape double quotes in variables for AppleScript string safety
ESC_APP="${APP_NAME//\"/\\\"}"
ESC_TITLE="${TITLE//\"/\\\"}"
osascript -e "display dialog \"截图已保存 ✅\n\n${ESC_APP}\n${ESC_TITLE}\n文本: ${TEXT_LEN} chars\" with title \"Appshot Captured\" buttons {\"OK\"} default button \"OK\" giving up after 2" 2>/dev/null

# Step 5: Copy snapshot ID to clipboard
echo "$SNAP_ID" | pbcopy

echo "✅ $APP_NAME — $TITLE ($TEXT_LEN chars)"
