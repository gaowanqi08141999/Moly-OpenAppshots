.PHONY: build install run clean setup-permissions notify doctor

BUILD_DIR := .build/debug
BINARY := $(BUILD_DIR)/MolyDaemon
NOTIFY_BIN := $(BUILD_DIR)/AppshotNotify

build:
	swift build

install: build
	@mkdir -p ~/.moly/bin
	@cp $(BINARY) ~/.moly/bin/molyd
	@chmod +x ~/.moly/bin/molyd
	@echo "Installed to ~/.moly/bin/molyd"
	@echo ""
	@echo "Restart daemon:"
	@echo "  killall molyd 2>/dev/null; ~/.moly/bin/molyd &"
	@echo ""
	@echo "Then verify permissions:"
	@echo "  make doctor"

doctor:
	@echo "=== Moly Health Check ==="
	@echo ""
	@echo "1. Daemon running?"
	@curl -sf http://127.0.0.1:19876/health > /dev/null 2>&1 && echo "   ✅ Daemon is running" || echo "   ❌ Daemon NOT running — run: ~/.moly/bin/molyd &"
	@echo ""
	@echo "2. Correct binary path?"
	@ps aux 2>/dev/null | grep -q "\.moly/bin/molyd" && echo "   ✅ Running from ~/.moly/bin/molyd" || echo "   ⚠️  Check with: ps aux | grep molyd"
	@echo ""
	@echo "3. Accessibility permission?"
	@curl -sf http://127.0.0.1:19876/axdiag | python3 -c "
import json,sys
d=json.load(sys.stdin)
if d.get('ax_trusted'):
    print('   ✅ AX trusted')
    print(f'      Test: {d.get(\"ax_test\",\"?\")}')
else:
    print('   ❌ AX NOT trusted — PERMISSION MISSING')
    print('   FIX: Settings → Privacy → Accessibility')
    print('   → + → ⌘⇧G → ~/.moly/bin/molyd → Open')
" || echo "   ❌ Cannot reach daemon"
	@echo ""
	@echo "4. Screen Recording permission?"
	@curl -sf -X POST http://127.0.0.1:19876/capture | python3 -c "
import json,sys
d=json.load(sys.stdin)
if d.get('textLength',0) > 0:
    print(f'   ✅ Capture OK ({d.get(\"textLength\",\"?\")} chars)')
else:
    print('   ⚠️  Text is 0 — check Screen Recording permission')
" || echo "   ⚠️  Capture failed — daemon may need permissions"
	@echo ""
	@echo "=== Done ==="

notify:
	swift build --target AppshotNotify

run: build
	$(BINARY)

clean:
	swift package clean
	rm -rf ~/snapshots

setup-permissions:
	@echo "=== Setting up macOS Permissions ==="
	@echo ""
	@echo "1. Screen Recording:"
	@echo "   System Preferences → Privacy & Security → Screen Recording"
	@echo "   → Enable 'MolyDaemon' (or your terminal app)"
	@echo ""
	@echo "2. Accessibility:"
	@echo "   System Preferences → Privacy & Security → Accessibility"
	@echo "   → Enable 'MolyDaemon' (or your terminal app)"
	@echo ""
	@echo "After granting permissions, restart the daemon."

entitlements:
	codesign --force --sign - --entitlements entitlements/capture.entitlements $(BINARY)

test-health:
	curl -s http://127.0.0.1:19876/health

test-capture:
	curl -s -X POST http://127.0.0.1:19876/capture

test-list:
	curl -s http://127.0.0.1:19876/snapshots
