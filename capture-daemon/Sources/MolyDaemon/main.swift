import Foundation

// MARK: - Entry Point

// ── CLI Mode: --setup → run permission wizard and exit ──
if CommandLine.arguments.contains("--setup") {
    _ = SetupHelper.run()
    exit(0)
}

print("Moly Daemon v0.1.0")
print("")

// ── Path Guard: enforce fixed install path for macOS TCC permissions ──
let expectedPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".moly/bin/molyd").path
if let actualPath = Bundle.main.executablePath {
    let resolvedActual = (actualPath as NSString).resolvingSymlinksInPath
    let resolvedExpected = (expectedPath as NSString).resolvingSymlinksInPath
    if resolvedActual != resolvedExpected {
        print("╔════════════════════════════════════════════════════════════════╗")
        print("║  ⚠️  WARNING: Daemon running from unexpected path            ║")
        print("╠════════════════════════════════════════════════════════════════╣")
        print("║  Current:  \(resolvedActual)                                  ")
        print("║  Expected: \(resolvedExpected)                                ")
        print("╠════════════════════════════════════════════════════════════════╣")
        print("║  macOS permissions (Screen Recording / Accessibility) are    ║")
        print("║  bound to the binary PATH. Running from a different path     ║")
        print("║  means those permissions WILL NOT APPLY.                     ║")
        print("║                                                              ║")
        print("║  FIX:                                                        ║")
        print("║  1. Kill this daemon:   killall MolyDaemon                  ║")
        print("║  2. Copy to fix path:   cp \(resolvedActual) \(resolvedExpected)")
        print("║  3. Restart:            \(resolvedExpected) &                 ")
        print("║  4. Grant permissions in System Settings → Privacy           ║")
        print("╚════════════════════════════════════════════════════════════════╝")
        print("")
    }
} else {
    print("[Warning] Could not determine executable path")
}

let snapshotDir = ProcessInfo.processInfo.environment["MOLY_SNAPSHOT_DIR"]
    ?? "~/snapshots"
let portStr = ProcessInfo.processInfo.environment["MOLY_PORT"] ?? "19876"
let port = UInt16(portStr) ?? 19876

// Initialize components
let engine = CaptureEngine()
let storage: StorageEngine
do {
    storage = try StorageEngine(basePath: snapshotDir)
    print("[Storage] \(snapshotDir)")
} catch {
    print("[Storage] Failed to init: \(error)")
    exit(1)
}

// Resolve paths for notification assets (copied by install.sh to ~/.moly/)
let home = FileManager.default.homeDirectoryForCurrentUser.path
let notifyScriptPath = "\(home)/.moly/notify.js"
let iconPath = "\(home)/.moly/Moly.png"
let flashScriptPath = "\(home)/.moly/flash.js"

// Start hotkey listener in background (⌃⌥⌘Space)
let hotkey = HotkeyListener(
    engine: engine,
    storage: storage,
    notifyScriptPath: FileManager.default.fileExists(atPath: notifyScriptPath) ? notifyScriptPath : nil,
    iconPath: FileManager.default.fileExists(atPath: iconPath) ? iconPath : nil,
    flashScriptPath: FileManager.default.fileExists(atPath: flashScriptPath) ? flashScriptPath : nil
)

let hotkeyThread = Thread {
    hotkey.start()
}
hotkeyThread.name = "hotkey-listener"
hotkeyThread.start()

// Start IPC server (blocking)
let server = IPCServer(port: port, engine: engine, storage: storage)
do {
    try server.start()
} catch {
    print("[IPC] Server error: \(error)")
    exit(1)
}
