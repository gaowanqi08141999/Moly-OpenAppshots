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

        // Check TCC database (definitive check — unaffected by Terminal inheritance)
        if checkOwnAccessibilityTCC(binPath: binPath) {
            print("│  \(check) Already granted (TCC entry + hash verified)")
            print("└──────────────────────────────────────────────────────────────")
            return true
        }

        // Try auto-grant: write CDHash-based csreq to TCC
        print("│  \(arrow) Attempting automatic TCC registration...")
        if autoGrantMolydAccessibility(binPath: binPath) {
            print("│  \(check) TCC entry created for current binary hash")
            print("│  💡 Run 'molyd --setup' again after every rebuild.")
            print("└──────────────────────────────────────────────────────────────")
            return true
        }

        // Auto-grant failed — guide user manually
        print("│  \(cross) Could not auto-register. Please add manually:")
        print("│")
        print("│  ┌─────────────────────────────────────────────────────────┐")
        print("│  │  System Settings will open to Accessibility            │")
        print("│  │  → Click [+] → ⌘⇧G → paste:                           │")
        print("│  │    \(binPath)")
        print("│  │  → Open → Toggle ON ✅ → Press Enter here             │")
        print("│  └─────────────────────────────────────────────────────────┘")
        print("│")

        let openTask = Process()
        openTask.launchPath = "/usr/bin/open"
        openTask.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        try? openTask.run()

        print("│  Press Enter after enabling molyd in Accessibility...")
        _ = readLine()

        if checkOwnAccessibilityTCC(binPath: binPath) {
            print("│  \(check) TCC entry confirmed. Restart daemon to apply.")
            print("└──────────────────────────────────────────────────────────────")
            return true
        }

        print("│  \(cross) Still not detected. Restart and re-run --setup.")
        print("└──────────────────────────────────────────────────────────────")
        return false
    }

    /// Auto-grant Accessibility to the current molyd binary.
    /// For ad-hoc signed binaries, TCC uses CDHash-based csreq (type=8).
    private static func autoGrantMolydAccessibility(binPath: String) -> Bool {
        guard let cdhashHex = getCurrentCDHash(binPath: binPath),
              let cdhashBytes = hexToBytes(cdhashHex) else { return false }

        // Build csreq: fade0c00 + len(4) + version(4) + type=8(4) + id_len(4) + cdhash(20)
        var blob = Data()
        blob.append(contentsOf: [0xfa, 0xde, 0x0c, 0x00])
        var totalLen = UInt32(20 + cdhashBytes.count).bigEndian
        blob.append(Data(bytes: &totalLen, count: 4))
        var version = UInt32(1).bigEndian; blob.append(Data(bytes: &version, count: 4))
        var rtype = UInt32(8).bigEndian; blob.append(Data(bytes: &rtype, count: 4))
        var idLen = UInt32(cdhashBytes.count).bigEndian
        blob.append(Data(bytes: &idLen, count: 4))
        blob.append(contentsOf: cdhashBytes)

        // Write to TCC
        let tccDB = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        guard FileManager.default.fileExists(atPath: tccDB) else { return false }

        var db: OpaquePointer?
        guard sqlite3_open(tccDB, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }

        let now = Int(Date().timeIntervalSince1970)
        var stmt: OpaquePointer?

        // Check existing
        let checkSQL = "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client=?"
        guard sqlite3_prepare_v2(db, checkSQL, -1, &stmt, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(stmt, 1, binPath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        let exists = sqlite3_step(stmt) == SQLITE_ROW
        sqlite3_finalize(stmt)

        if exists {
            let updSQL = "UPDATE access SET auth_value=2, auth_reason=3, csreq=?, last_modified=?, flags=NULL, policy_id=NULL WHERE service='kTCCServiceAccessibility' AND client=?"
            guard sqlite3_prepare_v2(db, updSQL, -1, &stmt, nil) == SQLITE_OK else { return false }
            _ = blob.withUnsafeBytes { ptr in sqlite3_bind_blob(stmt, 1, ptr.baseAddress, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            sqlite3_bind_int64(stmt, 2, Int64(now))
            sqlite3_bind_text(stmt, 3, binPath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            let insSQL = "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, last_modified) VALUES ('kTCCServiceAccessibility', ?, 1, 2, 3, 1, ?, ?)"
            guard sqlite3_prepare_v2(db, insSQL, -1, &stmt, nil) == SQLITE_OK else { return false }
            sqlite3_bind_text(stmt, 1, binPath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            _ = blob.withUnsafeBytes { ptr in sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            sqlite3_bind_int64(stmt, 3, Int64(now))
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else { sqlite3_finalize(stmt); return false }
        sqlite3_finalize(stmt)

        // Restart tccd
        let kickstart = Process()
        kickstart.launchPath = "/bin/launchctl"
        kickstart.arguments = ["kickstart", "gui/\(getuid())/com.apple.tccd"]
        kickstart.standardOutput = FileHandle.nullDevice
        kickstart.standardError = FileHandle.nullDevice
        try? kickstart.run()
        kickstart.waitUntilExit()

        return true
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
        let chromeBundleID = "com.google.Chrome"
        let fm = FileManager.default

        guard fm.fileExists(atPath: chromePath) else {
            print("│  ⏭️  Chrome not installed — skipping")
            print("└──────────────────────────────────────────────────────────────")
            return true
        }

        // Step 1: Set AXManualAccessibility flag + Chrome policy + preferences
        let defaultsTask = Process()
        defaultsTask.launchPath = "/usr/bin/defaults"
        defaultsTask.arguments = ["write", "com.google.Chrome", "AXManualAccessibility", "-bool", "true"]
        try? defaultsTask.run()
        defaultsTask.waitUntilExit()

        // Chrome managed policy (AccessibilityEnabled)
        writeChromePolicy()
        // Chrome internal preferences (accessibility.screenReader)
        writeChromePreferences()

        // Step 2: Check if Chrome already has Accessibility permission
        if checkTCCAccessibility(client: chromeBundleID) {
            print("│  \(check) Chrome Accessibility already granted")
            print("│  \(check) AXManualAccessibility + policy + prefs set")
            print("│")
            print("│  ⚠️  If you haven't ⌘Q quit + reopened Chrome yet, do it now!")
            print("└──────────────────────────────────────────────────────────────")
            return true
        }

        // Step 3: Try to auto-add Chrome to TCC (works for codesigned app bundles)
        print("│  \(arrow) Attempting automatic TCC registration...")

        if autoGrantChromeAccessibility(bundleID: chromeBundleID, appPath: chromePath) {
            print("│  \(check) Chrome Accessibility TCC entry created")
            print("│  \(check) AXManualAccessibility flag set")
            print("│")
            print("│  🔴 REQUIRED: ⌘Q quit Chrome completely, then reopen it.")
            print("│     (Chrome only activates AX bridge on startup)")
            print("└──────────────────────────────────────────────────────────────")
            return true
        }

        // Step 4: Auto-grant failed — guide user manually
        print("│  \(cross) Could not auto-configure. Please add manually:")
        print("│")
        print("│  ┌─────────────────────────────────────────────────────────┐")
        print("│  │  System Settings will open to Accessibility            │")
        print("│  │  → Click [+] → Find 'Google Chrome' → Toggle ON ✅     │")
        print("│  │  → Press Enter when done                              │")
        print("│  └─────────────────────────────────────────────────────────┘")
        print("│")

        let openTask = Process()
        openTask.launchPath = "/usr/bin/open"
        openTask.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        try? openTask.run()

        print("│  Press Enter after enabling Chrome in Accessibility...")
        _ = readLine()

        if checkTCCAccessibility(client: chromeBundleID) {
            print("│  \(check) Chrome Accessibility detected!")
        } else {
            print("│  \(cross) Not detected. ⌘Q restart Chrome may help.")
        }
        print("│")
        print("│  🔴 REQUIRED: ⌘Q quit Chrome completely, then reopen it.")
        print("└──────────────────────────────────────────────────────────────")
        return true
    }

    /// Auto-grant Accessibility to Chrome by writing its codesign requirement
    /// to the TCC database. Chrome is an Apple-notarized app bundle with a stable
    /// code signature, so the csreq blob is deterministic.
    private static func autoGrantChromeAccessibility(bundleID: String, appPath: String) -> Bool {
        let tccDB = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path

        guard FileManager.default.fileExists(atPath: tccDB) else { return false }

        // Get Chrome's designated code requirement
        let task = Process()
        task.launchPath = "/usr/bin/codesign"
        task.arguments = ["-d", "-r", "-", appPath]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        // Parse: designated => <requirement text>
        guard let reqStart = output.range(of: "=> ") else { return false }
        let reqText = String(output[reqStart.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Compile requirement text → binary blob
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(reqText as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else { return false }

        var cfData: CFData?
        guard SecRequirementCopyData(req, [], &cfData) == errSecSuccess,
              let csreqBlob = cfData as Data? else { return false }

        // Write to TCC
        var db: OpaquePointer?
        guard sqlite3_open(tccDB, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }

        let now = Int(Date().timeIntervalSince1970)

        // Check existing
        var stmt: OpaquePointer?
        let checkSQL = "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client=?"
        guard sqlite3_prepare_v2(db, checkSQL, -1, &stmt, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(stmt, 1, bundleID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        let exists = sqlite3_step(stmt) == SQLITE_ROW
        sqlite3_finalize(stmt)

        if exists {
            let updSQL = "UPDATE access SET auth_value=2, auth_reason=3, csreq=?, last_modified=? WHERE service='kTCCServiceAccessibility' AND client=?"
            guard sqlite3_prepare_v2(db, updSQL, -1, &stmt, nil) == SQLITE_OK else { return false }
            _ = csreqBlob.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 1, ptr.baseAddress, Int32(csreqBlob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            sqlite3_bind_int64(stmt, 2, Int64(now))
            sqlite3_bind_text(stmt, 3, bundleID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            let insSQL = "INSERT INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, last_modified) VALUES ('kTCCServiceAccessibility', ?, 0, 2, 3, 1, ?, ?)"
            guard sqlite3_prepare_v2(db, insSQL, -1, &stmt, nil) == SQLITE_OK else { return false }
            sqlite3_bind_text(stmt, 1, bundleID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            _ = csreqBlob.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(csreqBlob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            sqlite3_bind_int64(stmt, 3, Int64(now))
        }

        let result = sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        guard result == SQLITE_DONE else { return false }

        // Restart tccd to pick up changes immediately
        let kickstart = Process()
        kickstart.launchPath = "/bin/launchctl"
        kickstart.arguments = ["kickstart", "gui/\(getuid())/com.apple.tccd"]
        kickstart.standardOutput = FileHandle.nullDevice
        kickstart.standardError = FileHandle.nullDevice
        try? kickstart.run()
        kickstart.waitUntilExit()

        return true
    }

    /// Write Chrome managed policy to force accessibility on all pages.
    private static func writeChromePolicy() {
        let policyDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")
        try? FileManager.default.createDirectory(at: policyDir, withIntermediateDirectories: true)

        let policyFile = policyDir.appendingPathComponent("Policy.json")
        var policy: [String: Any] = ["AccessibilityEnabled": true]

        // Merge with existing policy if any
        if let data = try? Data(contentsOf: policyFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in existing { policy[k] = v }
        }

        if let data = try? JSONSerialization.data(withJSONObject: policy, options: .prettyPrinted) {
            try? data.write(to: policyFile)
        }
    }

    /// Write Chrome internal preferences to enable screen-reader accessibility mode.
    private static func writeChromePreferences() {
        let prefsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        let prefsFile = prefsDir.appendingPathComponent("Preferences")

        guard var prefs = (try? JSONSerialization.jsonObject(with: Data(contentsOf: prefsFile))) as? [String: Any] else {
            return
        }

        var acc = prefs["accessibility"] as? [String: Any] ?? [:]
        acc["enabled"] = true
        acc["imageLabels"] = true
        acc["screenReader"] = true
        prefs["accessibility"] = acc

        if let data = try? JSONSerialization.data(withJSONObject: prefs, options: []) {
            try? data.write(to: prefsFile)
        }
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

    private static func hexToBytes(_ hex: String) -> Data? {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard next > index else { return nil }
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

// MARK: - Data Extension

extension Data {
    func hexString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
