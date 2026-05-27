#!/bin/bash
# QClaw Appshot — Hotkey Capture Script (Standalone Share Version)
# Captures the CURRENT frontmost window without focus-stealing.
# After capture, the screenshot PNG is auto-copied to the system clipboard.
# All companion files (notify.js, QClaw.png) are in the same directory.

DAEMON_URL="${QCLAW_DAEMON_URL:-http://127.0.0.1:19876}"

# Step 1: Get the REAL frontmost app's PID — BEFORE any focus change
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
DIR_PATH=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dirPath',''))" 2>/dev/null)

if [ -z "$APP_NAME" ] || [ "$APP_NAME" = "?" ]; then
    osascript -e 'display notification "Capture failed — check daemon logs" with title "Appshot Error"' 2>/dev/null
    exit 1
fi

# Step 4: Copy screenshot PNG to clipboard ("screenshot → paste" UX)
PNG_PATH="${DIR_PATH}/screenshot.png"
if [ -f "$PNG_PATH" ]; then
    osascript -e "set the clipboard to (read (POSIX file \"$PNG_PATH\") as «class PNGf»)" 2>/dev/null
fi

# Step 5: Show Apple-style notification overlay (JXA)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTIFY_JS="${SCRIPT_DIR}/notify.js"
ICON_PNG="${SCRIPT_DIR}/QClaw.png"

if [ -f "$NOTIFY_JS" ]; then
    osascript -l JavaScript "$NOTIFY_JS" "${APP_NAME}" "${ICON_PNG}" &
fi

echo "✅ $APP_NAME — $TITLE ($TEXT_LEN chars)"
