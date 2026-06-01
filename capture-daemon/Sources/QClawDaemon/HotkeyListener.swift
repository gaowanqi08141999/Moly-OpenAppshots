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

    /// Copy PNG file to system clipboard (disk PNG now has metadata embedded by StorageEngine).
    private func copyPNGToClipboard(path: String) {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [
            "-e",
            "set the clipboard to (read (POSIX file \"\(path)\") as «class PNGf»)"
        ]
        do {
            try task.run()
        } catch {
            print("[Hotkey] ⚠️  Clipboard copy failed: \(error)")
        }
    }

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
