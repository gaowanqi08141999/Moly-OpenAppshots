.PHONY: build install run clean setup-permissions notify doctor

BUILD_DIR := .build/debug
BINARY := $(BUILD_DIR)/QClawDaemon
NOTIFY_BIN := $(BUILD_DIR)/AppshotNotify

build:
	swift build

install: build
	@mkdir -p ~/.qclaw-appshot/bin
	@cp $(BINARY) ~/.qclaw-appshot/bin/qclawd
	@chmod +x ~/.qclaw-appshot/bin/qclawd
	@echo "Installed to ~/.qclaw-appshot/bin/qclawd"
	@echo ""
	@echo "Restart daemon:"
	@echo "  killall qclawd 2>/dev/null; ~/.qclaw-appshot/bin/qclawd &"
	@echo ""
	@echo "Then verify permissions:"
	@echo "  make doctor"

doctor:
	@echo "=== QClaw Appshot Health Check ==="
	@echo ""
	@echo "1. Daemon running?"
	@curl -sf http://127.0.0.1:19876/health > /dev/null 2>&1 && echo "   ✅ Daemon is running" || echo "   ❌ Daemon NOT running — run: ~/.qclaw-appshot/bin/qclawd &"
	@echo ""
	@echo "2. Correct binary path?"
	@ps aux 2>/dev/null | grep -q "\.qclaw-appshot/bin/qclawd" && echo "   ✅ Running from ~/.qclaw-appshot/bin/qclawd" || echo "   ⚠️  Check with: ps aux | grep qclawd"
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
    print('   → + → ⌘⇧G → ~/.qclaw-appshot/bin/qclawd → Open')
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
	@echo "   → Enable 'QClawDaemon' (or your terminal app)"
	@echo ""
	@echo "2. Accessibility:"
	@echo "   System Preferences → Privacy & Security → Accessibility"
	@echo "   → Enable 'QClawDaemon' (or your terminal app)"
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
