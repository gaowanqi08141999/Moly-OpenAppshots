#!/bin/bash
DAEMON="/Users/jane/Desktop/QClaw-APPScreenshots/capture-daemon/.build/debug/QClawDaemon"
pkill -f QClawDaemon 2>/dev/null
sleep 1
QCLAW_SNAPSHOT_DIR="$HOME/snapshots" "$DAEMON" &
sleep 1
echo "Daemon PID: $!"
curl -s http://127.0.0.1:19876/health
