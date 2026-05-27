use std::sync::Arc;

use crate::DaemonState;

/// Start listening for the double-Command (⌘⌘) global hotkey.
///
/// Uses CGEvent API to register a global hotkey.
/// When triggered, performs a capture and updates daemon state.
pub fn start_listener(state: Arc<DaemonState>) {
    // TODO: Implement CGEvent global hotkey registration
    //
    // Pseudocode:
    // ```
    // let event_mask = CGEventMaskBit(kCGEventFlagsChanged);
    // let tap = CGEventTapCreate(
    //     kCGSessionEventTap,
    //     kCGHeadInsertEventTap,
    //     kCGEventTapOptionDefault,
    //     event_mask,
    //     hotkey_callback,
    //     &state as *const _ as *mut c_void,
    // );
    //
    // // In callback:
    // //   1. Check if both Command keys are pressed (modifier flag)
    // //   2. Debounce (prevent double-fire within 500ms)
    // //   3. Call state.capture_engine.capture_frontmost()
    // //   4. Save to storage
    // //   5. Update last_snapshot
    // ```
    //
    // Debounce logic:
    // ```
    // static LAST_TRIGGER: AtomicI64 = ...;
    // let now = SystemTime::now().duration_since(UNIX_EPOCH).as_millis();
    // if now - LAST_TRIGGER.load() < 500 { return; }
    // LAST_TRIGGER.store(now);
    // ```

    tracing::info!("Hotkey listener started (⌘⌘)");

    // Keep the thread alive — in real impl, CFRunLoop::run() here
    loop {
        std::thread::park();
    }
}
