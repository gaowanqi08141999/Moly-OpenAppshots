#!/usr/bin/env python3
"""Moly Doctor — one-command health check for all permissions and daemon status."""
import json, subprocess, sys, urllib.request, urllib.error

DAEMON = "http://127.0.0.1:19876"
ok, fail, warn = "✅", "❌", "⚠️"

def check_daemon():
    try:
        with urllib.request.urlopen(f"{DAEMON}/health", timeout=2) as resp:
            return json.loads(resp.read()).get("status") == "ok"
    except:
        return False

def check_path():
    result = subprocess.run(["ps", "aux"], capture_output=True, text=True)
    return ".moly/bin/molyd" in result.stdout

def check_ax():
    try:
        with urllib.request.urlopen(f"{DAEMON}/axdiag", timeout=2) as resp:
            d = json.loads(resp.read())
            return d.get("ax_trusted", False), d.get("ax_test", "?")
    except:
        return False, "daemon unreachable"

def check_capture():
    try:
        req = urllib.request.Request(f"{DAEMON}/capture", method="POST")
        with urllib.request.urlopen(req, timeout=5) as resp:
            d = json.loads(resp.read())
            return d.get("textLength", 0)
    except:
        return -1

print("=== Moly Doctor ===")
print()

print("1. Daemon running?")
if check_daemon():
    print(f"   {ok} Daemon is running")
else:
    print(f"   {fail} Daemon NOT running — run: ~/.moly/bin/molyd &")
    sys.exit(1)

print()
print("2. Correct binary path?")
if check_path():
    print(f"   {ok} Running from ~/.moly/bin/molyd")
else:
    print(f"   {warn} Check with: ps aux | grep molyd")

print()
print("3. Accessibility permission?")
trusted, ax_test = check_ax()
if trusted:
    print(f"   {ok} AX trusted ({ax_test})")
else:
    print(f"   {fail} AX NOT trusted — PERMISSION MISSING")
    print("   FIX: System Settings → Privacy → Accessibility")
    print("   → + → ⌘⇧G → ~/.moly/bin/molyd → Open")

print()
print("4. Screen Recording permission?")
text_len = check_capture()
if text_len > 0:
    print(f"   {ok} Capture OK ({text_len} chars)")
elif text_len == 0:
    print(f"   {warn} Text is 0 — check Screen Recording permission")
else:
    print(f"   {warn} Capture failed — daemon may need permissions")

print()
print("=== Done ===")
