.PHONY: build install run clean doctor

BUILD_DIR := .build/debug
BINARY := $(BUILD_DIR)/MolyDaemon

build:
	swift build

install: build
	@mkdir -p ~/.moly/bin
	@cp $(BINARY) ~/.moly/bin/molyd
	@chmod +x ~/.moly/bin/molyd
	@cp Sources/MolyNotify/notify.js ~/.moly/ 2>/dev/null || true
	@cp Sources/MolyNotify/flash.js ~/.moly/ 2>/dev/null || true
	@echo "Installed to ~/.moly/bin/molyd"
	@echo ""
	@echo "Restart daemon:"
	@echo "  killall molyd 2>/dev/null; ~/.moly/bin/molyd &"
	@echo ""
	@echo "Verify: make doctor"

run: build
	$(BINARY)

clean:
	swift package clean

doctor:
	@python3 doctor.py
