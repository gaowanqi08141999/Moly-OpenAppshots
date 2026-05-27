#!/bin/bash
# QClaw Appshot — Hotkey Capture Script
# Called by Automator Quick Action or any hotkey tool.
# Captures the CURRENT frontmost window (whatever the user is looking at),
# saves it, and shows a notification.

DAEMON_URL="${QCLAW_DAEMON_URL:-http://127.0.0.1:19876}"

# Trigger capture
RESPONSE=$(curl -s -X POST "$DAEMON_URL/capture" 2>&1)
if [ $? -ne 0 ]; then
    osascript -e "display notification \"Daemon not reachable on $DAEMON_URL\" with title \"Appshot Error\"" 2>/dev/null
    exit 1
fi

# Parse result
APP_NAME=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('appName','?'))" 2>/dev/null)
TITLE=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('windowTitle','')[:60])" 2>/dev/null)
TEXT_LEN=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('textLength',0))" 2>/dev/null)
SNAP_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)

if [ -z "$APP_NAME" ] || [ "$APP_NAME" = "?" ]; then
    osascript -e "display notification \"Capture failed — check daemon logs\" with title \"Appshot Error\"" 2>/dev/null
    exit 1
fi

# Show notification
osascript -e "display notification \"${TITLE}\nText: ${TEXT_LEN} chars\" with title \"📸 ${APP_NAME}\" subtitle \"Appshot captured\"" 2>/dev/null

# Also copy snapshot ID to clipboard for easy reference
echo "$SNAP_ID" | pbcopy

echo "✅ $APP_NAME — $TITLE ($TEXT_LEN chars)"
