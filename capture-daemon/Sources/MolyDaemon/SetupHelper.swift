import Cocoa
import ScreenCaptureKit
import SQLite3

/// One-shot permission setup helper.
/// Runs systematic checks and triggers system permission dialogs for each missing permission.
/// Call `SetupHelper.run()` before starting the daemon, or via `molyd --setup`.
final class SetupHelper {

    private static let check = "  ✅"
    private static let cross = "  ❌"
    private static let arrow = "  →"

    /// Run the full permission setup flow, returning true if everything is OK.
    @discardableResult
    static func run(launchAgentMode: Bool = false) -> Bool {
        print("")
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║           🐱  Moly Permission Setup                         ║")
        print("║   One-time setup for all permissions Moly needs             ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print("")

        var allOK = true

        // ── 1. Accessibility for molyd ──
        allOK = setupAccessibility() && allOK

        // ── 2. Screen Recording for molyd ──
        allOK = setupScreenRecording() && allOK

        // ── 3. Chrome Accessibility ──
        allOK = setupChromeAccessibility() && allOK

        // ── Summary ──
        print("")
        print("──────────────────────────────────────────────────────────────")
        if allOK {
            print("🎉  All permissions granted! Moly is ready to capture.")
        } else {
            print("⚠️  Some permissions still missing. See above for instructions.")
        }
        print("──────────────────────────────────────────────────────────────")
        print("")
        print("Next steps:")
        print("  1. If you just granted permissions, RESTART the daemon:")
        print("     killall molyd; ~/.moly/bin/molyd &")
        print("  2. If you added Chrome to Accessibility, ⌘Q quit & reopen Chrome")
        print("  3. Verify: make doctor    (or just press ⌃⌥⌘Space!)")
        print("")

        return allOK
    }

    // MARK: - Accessibility (molyd)

    private static func setupAccessibility() -> Bool {
        print("┌─ Permission 1/3: Accessibility (molyd)")
        print("│  Needed for: reading window text, global hotkey")

        guard let binPath = Bundle.main.executablePath else {
            print("│  \(cross) Cannot determine binary path")
            print("└──────────────────────────────────────────────────────────────")
            return false
        }

        // ⚠️  CGEvent tap is NOT reliable when running from Terminal:
        // Terminal.app inherits its Accessibility permission to child processes,
        // so tapCreate succeeds even though molyd has NO TCC entry.
        // The ONLY definitive check is: does this binary have its own TCC entry?
        let hasTCC = checkOwnAccessibilityTCC(binPath: binPath)

        if hasTCC {
            // Also verify with tap (belt and suspenders)
            let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: eventMask,
                callback: { _, _, event, _ in Unmanaged.passRetained(event) },
                userInfo: nil
            )
            if let tap = tap {
                CFMachPortInvalidate(tap)
                print("│  \(check) Already granted (TCC entry + tap verified)")
                print("└──────────────────────────────────────────────────────────────")
                return true
            }
            // Tap failed but TCC exists — unusual, maybe hash mismatch
            print("│  \(arrow) TCC entry exists but tap failed. Binary hash may have changed.")
        } else {
            print("│  \(cross) No TCC Accessibility entry for this binary")
            print("│")
            print("│  ⚠️  If daemon runs from Terminal, it appears to work because")
            print("│     Terminal inherits its own Accessibility permission.")
            print("│     But after reboot (LaunchAgent / launchd), it will FAIL.")
        }

        // Either no TCC entry, or tap failed — guide user
        print("│")
        print("│  ┌─────────────────────────────────────────────────────────┐")
        print("│  │  STEP 1: System Settings will open to Accessibility    │")
        print("│  │  STEP 2: Click [+] at the bottom of the list           │")
        print("│  │  STEP 3: Press ⌘⇧G, paste this path, click Open:      │")
        print("│  │          \(binPath)")
        print("│  │  STEP 4: Make sure the switch next to molyd is ON ✅    │")
        print("│  │  STEP 5: Press Enter in this terminal to continue     │")
        print("│  └─────────────────────────────────────────────────────────┘")
        print("│")

        let openTask = Process()
        openTask.launchPath = "/usr/bin/open"
        openTask.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        try? openTask.run()

        print("│  Press Enter after you've enabled molyd in Accessibility...")
        _ = readLine()

        // Re-check TCC
        if checkOwnAccessibilityTCC(binPath: binPath) {
            print("│  \(check) TCC entry confirmed. Restart daemon for it to take effect.")
            print("└──────────────────────────────────────────────────────────────")
            return true
        }

        print("│  \(cross) TCC entry still not detected. You may need to")
        print("│     restart and re-run 'molyd --setup'.")
        print("└──────────────────────────────────────────────────────────────")
        return false
    }

    /// Check TCC database for this binary's Accessibility entry.
    /// Returns true only if the entry exists with auth_value=2 AND the cdhash matches.
    private static func checkOwnAccessibilityTCC(binPath: String) -> Bool {
        let tccDB = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path

        guard FileManager.default.fileExists(atPath: tccDB) else { return false }

        var db: OpaquePointer?
        guard sqlite3_open(tccDB, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }

        // Check if entry exists with auth=2
        var stmt: OpaquePointer?
        let sql = "SELECT csreq FROM access WHERE service='kTCCServiceAccessibility' AND client=? AND auth_value=2"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }

        sqlite3_bind_text(stmt, 1, binPath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            sqlite3_finalize(stmt)
            return false
        }

        // Verify cdhash matches current binary
        if let blobPtr = sqlite3_column_blob(stmt, 0) {
            let blobLen = sqlite3_column_bytes(stmt, 0)
            let blob = Data(bytes: blobPtr, count: Int(blobLen))

            // Parse csreq: magic(4) + len(4) + version(4) + type(4) + id_len(4) + id
            if blobLen > 24 {
                let _ /* type */ = blob.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) }
                let rawIdLen = blob.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt32.self) }
                let idLen = UInt32(bigEndian: rawIdLen)
                if Int(idLen) <= blobLen - 20 {
                    let storedCDHash = blob.subdata(in: 20..<20+Int(idLen)).hexString()

                    // Get current binary cdhash
                    if let currentCDHash = getCurrentCDHash(binPath: binPath),
                       storedCDHash == currentCDHash {
                        sqlite3_finalize(stmt)
                        return true
                    }
                }
            }
        }

        sqlite3_finalize(stmt)
        return false
    }

    private static func getCurrentCDHash(binPath: String) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/codesign"
        task.arguments = ["-d", "-r", "-", binPath]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if let range = output.range(of: "cdhash H\"") {
            let start = range.upperBound
            if let end = output[start...].firstIndex(of: "\"") {
                return String(output[start..<end])
            }
        }
        return nil
    }

    // MARK: - Screen Recording (molyd)

    private static func setupScreenRecording() -> Bool {
        print("┌─ Permission 2/3: Screen Recording (molyd)")
        print("│  Needed for: capturing window screenshots")

        // Test permission by trying to access screen content
        let sem = DispatchSemaphore(value: 0)
        var hasPermission = false
        var didCheck = false

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                // If no error, we have permission (or no windows visible — edge case)
                hasPermission = true
                if content.windows.isEmpty {
                    // Double check: empty windows might mean no windows on screen right now
                    // But no error means Screen Recording permission is OK
                }
            } catch {
                let msg = error.localizedDescription.lowercased()
                // SCShareableContent throws an auth-related error when permission is missing
                if msg.contains("not authorized") || msg.contains("declined") ||
                   msg.contains("screen") || msg.contains("recording") || msg.contains("capture") ||
                   msg.contains("invalid") && msg.contains("process") {
                    hasPermission = false
                } else {
                    // Other error (e.g. no displays) — assume permission OK
                    hasPermission = true
                }
            }
            didCheck = true
            sem.signal()
        }

        _ = sem.wait(timeout: .now() + 8)

        if didCheck && hasPermission {
            print("│  \(check) Already granted")
            print("└──────────────────────────────────────────────────────────────")
            return true
        }

        // Not granted — guide user
        guard let binPath = Bundle.main.executablePath else {
            print("│  \(cross) Cannot determine binary path")
            print("└──────────────────────────────────────────────────────────────")
            return false
        }

        print("│  \(cross) Not granted")
        print("│")
        print("│  ┌─────────────────────────────────────────────────────────┐")
        print("│  │  STEP 1: System Settings will open to Screen Recording │")
        print("│  │  STEP 2: Click [+] at the bottom of the list           │")
        print("│  │  STEP 3: Press ⌘⇧G, paste this path, click Open:      │")
        print("│  │          \(binPath)")
        print("│  │  STEP 4: Make sure the switch is ON ✅                  │")
        print("│  │  STEP 5: Press Enter in this terminal to continue     │")
        print("│  └─────────────────────────────────────────────────────────┘")
        print("│")

        let openTask = Process()
        openTask.launchPath = "/usr/bin/open"
        openTask.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"]
        try? openTask.run()

        print("│  Press Enter after you've enabled Screen Recording for molyd...")
        _ = readLine()

        // Re-test
        let sem2 = DispatchSemaphore(value: 0)
        var hasPermission2 = false
        Task {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                hasPermission2 = true
            } catch { }
            sem2.signal()
        }
        _ = sem2.wait(timeout: .now() + 8)

        if hasPermission2 {
            print("│  \(check) Permission granted — thank you!")
            print("└──────────────────────────────────────────────────────────────")
            return true
        }

        print("│  \(cross) Still not detected. A restart may be needed.")
        print("│     Run '~/.moly/bin/molyd --setup' again after granting.")
        print("└──────────────────────────────────────────────────────────────")
        return false
    }

    // MARK: - Chrome Accessibility

    private static func setupChromeAccessibility() -> Bool {
        print("┌─ Permission 3/3: Accessibility (Google Chrome)")
        print("│  Needed for: extracting web page text from Chrome tabs")
        print("│  Why: Chrome renders web content in sub-processes —")
        print("│       the AX bridge only activates when Chrome itself has")
        print("│       Accessibility permission.")

        let chromePath = "/Applications/Google Chrome.app"
        let fm = FileManager.default

        guard fm.fileExists(atPath: chromePath) else {
            print("│  ⏭️  Chrome not installed — skipping")
            print("└──────────────────────────────────────────────────────────────")
            return true  // non-blocking
        }

        // Set AXManualAccessibility flag (this is non-destructive and always needed)
        let defaultsTask = Process()
        defaultsTask.launchPath = "/usr/bin/defaults"
        defaultsTask.arguments = ["write", "com.google.Chrome", "AXManualAccessibility", "-bool", "true"]
        try? defaultsTask.run()
        defaultsTask.waitUntilExit()

        // Check if Chrome already has Accessibility permission in TCC
        if checkTCCAccessibility(client: "com.google.Chrome") {
            print("│  \(check) Chrome Accessibility already granted")
            print("│  \(check) AXManualAccessibility flag set")
            print("│")
            print("│  ⚠️  If you haven't ⌘Q quit + reopened Chrome yet, do it now!")
            print("└──────────────────────────────────────────────────────────────")
            return true
        }

        print("│  \(cross) Chrome not in Accessibility list")
        print("│")
        print("│  ┌─────────────────────────────────────────────────────────┐")
        print("│  │  STEP 1: System Settings will open to Accessibility    │")
        print("│  │  STEP 2: Click [+] at the bottom of the list           │")
        print("│  │  STEP 3: Find 'Google Chrome' in Applications          │")
        print("│  │  STEP 4: Toggle the switch ON ✅                        │")
        print("│  │  STEP 5: Press Enter in this terminal to continue     │")
        print("│  └─────────────────────────────────────────────────────────┘")
        print("│")

        let openTask = Process()
        openTask.launchPath = "/usr/bin/open"
        openTask.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        try? openTask.run()

        print("│  Press Enter after you've enabled Chrome in Accessibility...")
        _ = readLine()

        if checkTCCAccessibility(client: "com.google.Chrome") {
            print("│  \(check) Chrome Accessibility granted!")
        } else {
            print("│  \(cross) May need to restart Chrome to take effect.")
        }

        print("│")
        print("│  🔴 REQUIRED: ⌘Q quit Chrome completely, then reopen it.")
        print("│     (Chrome only activates AX bridge on startup)")
        print("└──────────────────────────────────────────────────────────────")
        return true
    }

    /// Quick check if a client has Accessibility permission in TCC.
    private static func checkTCCAccessibility(client: String) -> Bool {
        let tccDB = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        guard FileManager.default.fileExists(atPath: tccDB) else { return false }
        var db: OpaquePointer?
        guard sqlite3_open(tccDB, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client=? AND auth_value=2",
            -1, &stmt, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(stmt, 1, client, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        let result = sqlite3_step(stmt) == SQLITE_ROW
        sqlite3_finalize(stmt)
        return result
    }
}

// MARK: - Data Extension

extension Data {
    func hexString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
