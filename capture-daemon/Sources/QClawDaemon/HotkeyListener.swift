import Foundation
import Cocoa

/// Global hotkey listener — detects double-Command (⌘⌘) and triggers capture.
/// Uses CGEvent API for low-level keyboard event monitoring.
final class HotkeyListener: @unchecked Sendable {

    private var lastCommandPress: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.4  // 400ms window for double-press
    private var isRunning = false

    /// Called when the hotkey is triggered.
    var onTrigger: (() -> Void)?

    /// Start listening for ⌘⌘ (double Command key press).
    /// Requires Accessibility permission in System Preferences.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Check for accessibility permission
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            print("[HotkeyListener] ⚠️ Accessibility permission not granted.")
            print("  Please enable in: System Preferences → Privacy → Accessibility")
            return
        }

        // Monitor flags-changed events (modifier key state changes)
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard type == .flagsChanged else {
                    return Unmanaged.passRetained(event)
                }

                let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon!).takeUnretainedValue()
                listener.handleFlagsChanged(event: event)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = tap else {
            print("[HotkeyListener] ⚠️ Failed to create event tap. Check Accessibility permissions.")
            // Prompt user
            let opts2 = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts2)
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[HotkeyListener] ✅ Listening for ⌘⌘ (double Command key)")

        CFRunLoopRun()
    }

    private func handleFlagsChanged(event: CGEvent) {
        let flags = event.flags

        // Check if Command key was just pressed (not held from previous state)
        let cmdPressed = flags.contains(.maskCommand)

        if cmdPressed {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastCommandPress)

            if elapsed < debounceInterval && elapsed > 0.05 {
                // Double Command detected!
                print("[HotkeyListener] ⌘⌘ triggered!")
                DispatchQueue.main.async { [weak self] in
                    self?.onTrigger?()
                }
                // Reset to prevent triple-fire
                lastCommandPress = .distantPast
            } else {
                lastCommandPress = now
            }
        }
    }

    func stop() {
        isRunning = false
        // CFRunLoopStop would be called from outside the run loop
    }
}
