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

// Start hotkey listener in background
let hotkey = HotkeyListener()
hotkey.onTrigger = {
    Task {
        print("[Hotkey] Capturing...")
        do {
            let result = try await engine.captureFrontmost()
            let summary = try storage.save(result)
            print("[Hotkey] Captured: \(summary.appName) — \(summary.windowTitle)")
            print("[Hotkey]    Text: \(summary.textLength) chars, Elements: \(summary.elementCount)")
        } catch {
            print("[Hotkey] Capture failed: \(error)")
        }
    }
}

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
