import Foundation

// MARK: - Entry Point

print("QClaw Appshot Daemon v0.1.0")
print("")

let snapshotDir = ProcessInfo.processInfo.environment["QCLAW_SNAPSHOT_DIR"]
    ?? "~/snapshots"
let portStr = ProcessInfo.processInfo.environment["QCLAW_PORT"] ?? "19876"
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

// Resolve paths for notification assets (copied by install.sh to ~/.qclaw/)
let home = FileManager.default.homeDirectoryForCurrentUser.path
let notifyScriptPath = "\(home)/.qclaw/notify.js"
let iconPath = "\(home)/.qclaw/QClaw.png"

// Start hotkey listener in background (⌃⌥⌘Space)
let hotkey = HotkeyListener(
    engine: engine,
    storage: storage,
    notifyScriptPath: FileManager.default.fileExists(atPath: notifyScriptPath) ? notifyScriptPath : nil,
    iconPath: FileManager.default.fileExists(atPath: iconPath) ? iconPath : nil
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
