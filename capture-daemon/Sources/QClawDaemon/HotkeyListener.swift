import Foundation
import Cocoa

/// Global hotkey listener — detects ⌃⌥⌘Space and triggers PID-aware capture.
/// Uses CGEvent API for low-level keyboard event monitoring.
/// Requires Accessibility permission.
final class HotkeyListener: @unchecked Sendable {

    private var isRunning = false
    private let engine: CaptureEngine
    private let storage: StorageEngine
    private let notifyScriptPath: String?
    private let iconPath: String?
    private let flashScriptPath: String?

    init(engine: CaptureEngine,
         storage: StorageEngine,
         notifyScriptPath: String? = nil,
         iconPath: String? = nil,
         flashScriptPath: String? = nil) {
        self.engine = engine
        self.storage = storage
        self.notifyScriptPath = notifyScriptPath
        self.iconPath = iconPath
        self.flashScriptPath = flashScriptPath
    }

    /// Start listening for ⌃⌥⌘Space.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            print("[HotkeyListener] ⚠️  Accessibility permission not granted.")
            print("  → System Settings → Privacy & Security → Accessibility → Enable QClawDaemon")
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon!).takeUnretainedValue()
                return listener.handleKeyDown(event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = tap else {
            print("[HotkeyListener] ⚠️  Failed to create event tap.")
            let opts2 = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts2)
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[HotkeyListener] ✅  Listening for ⌃⌥⌘Space (press to capture)")

        CFRunLoopRun()
    }

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Space = 49, must have ⌃⌥⌘ pressed simultaneously
        guard keyCode == 49,
              flags.contains(.maskControl),
              flags.contains(.maskAlternate),
              flags.contains(.maskCommand) else {
            return Unmanaged.passRetained(event)
        }

        // Hotkey matched — consume the event (don't pass to other apps)
        print("[Hotkey] ⌃⌥⌘Space triggered!")

        // Immediate visual feedback (non-blocking)
        showFlash()

        Task { [weak self] in
            await self?.performCapture()
        }

        return nil
    }

    private func performCapture() async {
        do {
            // 1. Get the REAL frontmost app's PID via AppleScript
            // (NSWorkspace.frontmostApplication can return the daemon itself)
            let pid = try await getFrontmostPID()

            // 2. Capture that specific app
            let result = try await engine.captureApp(pid: pid)
            let summary = try storage.save(result)

            print("[Hotkey] ✅  Captured: \(summary.appName) — \(summary.windowTitle)")

            // 3. Copy screenshot PNG to clipboard
            let pngPath = summary.dirPath + "/screenshot.png"
            copyPNGToClipboard(path: pngPath)

            // 4. Show notification overlay
            showNotification(appName: summary.appName)

        } catch {
            print("[Hotkey] ❌  Capture failed: \(error)")
        }
    }

    /// Query System Events for the actual frontmost app PID.
    private func getFrontmostPID() async throws -> pid_t {
        let script = """
        tell application "System Events"
            get unix id of first process whose frontmost is true
        end tell
        """

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8),
                      let pid = pid_t(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    continuation.resume(throwing: CaptureError.noActiveApp)
                    return
                }
                continuation.resume(returning: pid)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Copy PNG file to system clipboard, embedding snapshot path in metadata.
    private func copyPNGToClipboard(path: String) {
        // Embed the snapshot directory path as PNG metadata
        // so agents can directly read local files instead of querying daemon.
        let dirPath = (path as NSString).deletingLastPathComponent
        let tempPath = embedPathInPNG(pngPath: path, snapshotDir: dirPath) ?? path

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [
            "-e",
            "set the clipboard to (read (POSIX file \"\(tempPath)\") as «class PNGf»)"
        ]
        do {
            try task.run()
        } catch {
            print("[Hotkey] ⚠️  Clipboard copy failed: \(error)")
        }

        // Clean up temp file if we created one
        if tempPath != path {
            try? FileManager.default.removeItem(atPath: tempPath)
        }
    }

    /// Embed a tEXt chunk (qclaw_path=<dir>) into PNG data before the IEND chunk.
    /// This lets agents extract the local snapshot directory from the pasted image.
    private func embedPathInPNG(pngPath: String, snapshotDir: String) -> String? {
        guard var data = try? Data(contentsOf: URL(fileURLWithPath: pngPath)) else { return nil }

        let keyword = "qclaw_path"
        let text = snapshotDir

        // Build tEXt chunk data: keyword + null + text
        var chunkData = Data()
        chunkData.append(contentsOf: keyword.utf8)
        chunkData.append(0) // null separator
        chunkData.append(contentsOf: text.utf8)

        // Build full chunk: 4-byte length + "tEXt" + data + 4-byte CRC32
        var chunk = Data()
        var length = UInt32(chunkData.count).bigEndian
        chunk.append(Data(bytes: &length, count: 4))
        chunk.append(contentsOf: "tEXt".utf8)
        chunk.append(chunkData)

        // CRC32 over type + data
        var crcData = Data("tEXt".utf8)
        crcData.append(chunkData)
        var crc = crc32(crcData).bigEndian
        chunk.append(Data(bytes: &crc, count: 4))

        // Insert before IEND (last 12 bytes: 4 len + "IEND" + 4 crc)
        guard data.count >= 12 else { return nil }
        let iendOffset = data.count - 12
        data.insert(contentsOf: chunk, at: iendOffset)

        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("qclaw_\(UUID().uuidString).png")
        do {
            try data.write(to: tempFile)
            return tempFile.path
        } catch {
            return nil
        }
    }

    /// Simple CRC32 implementation (Ethernet polynomial, PNG compatible).
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let lookupIndex = (crc ^ UInt32(byte)) & 0xFF
            crc = (crc >> 8) ^ crc32Table[Int(lookupIndex)]
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Pre-computed CRC32 lookup table (Ethernet polynomial 0xEDB88320).
    private let crc32Table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            table[i] = c
        }
        return table
    }()

    /// Screen flash feedback — called immediately on hotkey press.
    private func showFlash() {
        guard let scriptPath = flashScriptPath,
              FileManager.default.fileExists(atPath: scriptPath) else {
            return
        }

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-l", "JavaScript", scriptPath]
        do {
            try task.run()
        } catch {
            print("[Hotkey] ⚠️  Flash failed: \(error)")
        }
    }

    /// Show Apple-style notification via JXA notify.js.
    private func showNotification(appName: String) {
        guard let scriptPath = notifyScriptPath,
              FileManager.default.fileExists(atPath: scriptPath) else {
            return
        }

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        var args = ["-l", "JavaScript", scriptPath, appName]
        if let icon = iconPath {
            args.append(icon)
        }
        task.arguments = args
        do {
            try task.run()
        } catch {
            print("[Hotkey] ⚠️  Notification failed: \(error)")
        }
    }

    func stop() {
        isRunning = false
    }
}
