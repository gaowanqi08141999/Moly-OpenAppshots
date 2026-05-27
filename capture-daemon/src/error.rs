use std::collections::HashMap;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppshotError {
    #[error("No active application found")]
    NoActiveApplication,

    #[error("No visible window for the frontmost application")]
    NoVisibleWindow,

    #[error("ScreenCaptureKit: {0}")]
    ScreenCaptureError(String),

    #[error("Accessibility API: {0}")]
    AccessibilityError(String),

    #[error("Storage: {0}")]
    StorageError(#[from] std::io::Error),

    #[error("SQLite: {0}")]
    SqliteError(#[from] rusqlite::Error),

    #[error("Snapshot not found: {0}")]
    NotFound(String),
}

// ── Accessibility Tree ──

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AXNode {
    pub role: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub position: Option<AXPosition>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<AXSize>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub children: Vec<AXNode>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AXPosition {
    pub x: f64,
    pub y: f64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AXSize {
    pub width: f64,
    pub height: f64,
}

impl AXNode {
    /// Extract all text content from the accessibility tree,
    /// useful for sending to LLMs as plain text context.
    pub fn flatten_text(&self) -> String {
        let mut texts = Vec::new();
        self.collect_text(&mut texts);
        texts.join("\n")
    }

    fn collect_text(&self, texts: &mut Vec<String>) {
        if let Some(ref value) = self.value {
            let trimmed = value.trim();
            if !trimmed.is_empty() && trimmed.len() < 5000 {
                texts.push(format!("[{}] {}", self.role, trimmed));
            }
        }
        if let Some(ref title) = self.title {
            let trimmed = title.trim();
            if !trimmed.is_empty() {
                texts.push(format!("[{}:title] {}", self.role, trimmed));
            }
        }
        for child in &self.children {
            child.collect_text(texts);
        }
    }

    pub fn element_count(&self) -> usize {
        1 + self.children.iter().map(|c| c.element_count()).sum::<usize>()
    }
}

// ── Snapshot Metadata ──

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AppMetadata {
    pub bundle_id: String,
    pub name: String,
    pub window_title: String,
    pub pid: i32,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SnapshotMetadata {
    pub id: String,
    pub timestamp: String,  // ISO 8601
    pub app: AppMetadata,
    pub window_bounds: WindowBounds,
    pub image: ImageInfo,
    pub accessibility: AccessibilityInfo,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct WindowBounds {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ImageInfo {
    pub path: String,
    pub width: u32,
    pub height: u32,
    pub scale_factor: f64,
    pub format: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AccessibilityInfo {
    pub path: String,
    pub text_length: usize,
    pub element_count: usize,
}

// ── SnapshodPayload (Raw Capture Result) ──

pub struct RawCapture {
    pub png_data: Vec<u8>,
    pub ax_tree: AXNode,
    pub metadata: SnapshotMetadata,
}
