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

        // Check without prompting first (for logging)
        let checkOpts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        let alreadyTrusted = AXIsProcessTrustedWithOptions(checkOpts)
        if !alreadyTrusted {
            print("[HotkeyListener] ⚠️  Accessibility permission not granted.")
            print("  → Attempting to create event tap anyway (will trigger prompt on failure)")
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
            if !alreadyTrusted {
                // ⚠️  Do NOT call AXIsProcessTrustedWithOptions(prompt:true) here.
                // When daemon runs from launchd or a script, the TCC dialog can't
                // be shown and the call may block indefinitely.
                // Instead, guide the user to run --setup which handles prompting.
                print("[HotkeyListener] ⚠️  Accessibility permission NOT granted.")
                print("[HotkeyListener] → Run: ~/.moly/bin/molyd --setup")
                print("[HotkeyListener] → Or: System Settings → Privacy → Accessibility → add molyd")
                print("[HotkeyListener] → Then restart daemon: killall molyd; ~/.moly/bin/molyd &")
            } else {
                print("[HotkeyListener] ⚠️  Failed to create event tap even though trusted.")
                print("[HotkeyListener] → Binary hash may have changed. Rerun: molyd --setup")
            }
            // Don't return — continue running IPC server (capture via API still works)
            // Only the hotkey won't work until permissions are granted.
            isRunning = false
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
            let pid = try await getFrontmostPID()

            // 2. Get app name early (fast) so we can show notification immediately
            let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""

            // 3. Show notification NOW — in parallel with capture (saves ~1s perceived latency)
            showNotification(appName: appName)

            // 4. Capture that specific app
            let result = try await engine.captureApp(pid: pid)
            let summary = try storage.save(result)

            print("[Hotkey] ✅  Captured: \(summary.appName) — \(summary.windowTitle)")

            // 5. Copy screenshot PNG to clipboard
            let pngPath = summary.dirPath + "/screenshot.png"
            copyPNGToClipboard(path: pngPath)

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
