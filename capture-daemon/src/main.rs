//! QClaw Appshot Daemon — macOS native capture engine
//!
//! Architecture:
//!   main.rs          Entry point, starts IPC server + hotkey listener
//!   ipc.rs           Unix Socket HTTP server (hyper)
//!   capture.rs       ScreenCaptureKit + Accessibility API dual capture
//!   storage.rs       Filesystem + SQLite snapshot storage
//!   hotkey.rs        CGEvent global hotkey (⌘⌘)
//!
//! IPC endpoints:
//!   POST   /capture           Trigger a capture
//!   GET    /snapshots          List saved snapshots
//!   GET    /snapshots/:id      Get full snapshot
//!   DELETE /snapshots/:id      Delete a snapshot
//!   GET    /screenshots/:id    Get screenshot image
//!   GET    /health             Health check

mod capture;
mod error;
mod hotkey;
mod ipc;
mod storage;

use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct DaemonState {
    pub storage: storage::StorageEngine,
    pub capture_engine: capture::CaptureEngine,
    pub last_snapshot: Mutex<Option<storage::SnapshotSummary>>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    let snapshot_dir = dirs_next().unwrap_or_else(|| PathBuf::from("."));
    let base_path = snapshot_dir.join("snapshots");

    let state = Arc::new(DaemonState {
        storage: storage::StorageEngine::new(&base_path)?,
        capture_engine: capture::CaptureEngine::new()?,
        last_snapshot: Mutex::new(None),
    });

    // Start hotkey listener in background
    let hotkey_state = state.clone();
    std::thread::spawn(move || {
        hotkey::start_listener(hotkey_state);
    });

    // Start IPC server (blocking)
    let socket_path = "/tmp/qclaw-appshot.sock";
    // Remove stale socket if exists
    let _ = std::fs::remove_file(socket_path);

    tracing::info!("QClaw Appshot Daemon starting on {}", socket_path);
    ipc::start_server(socket_path, state).await?;

    Ok(())
}

fn dirs_next() -> Option<PathBuf> {
    std::env::var("QCLAW_SNAPSHOT_DIR")
        .ok()
        .map(PathBuf::from)
        .or_else(|| {
            dirs::home_dir().map(|h| h.join("snapshots"))
        })
}
