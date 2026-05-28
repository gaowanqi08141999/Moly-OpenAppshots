.PHONY: build install run clean setup-permissions notify

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
	@echo "Restart with: killall qclawd; sleep 1; ~/.qclaw-appshot/bin/qclawd &"

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
