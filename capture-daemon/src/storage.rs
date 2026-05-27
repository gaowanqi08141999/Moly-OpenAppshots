use std::path::{Path, PathBuf};

use rusqlite::Connection;

use crate::error::{AppshotError, RawCapture, SnapshotMetadata};

/// Storage engine: filesystem for large blobs (PNG, JSON), SQLite for index.
pub struct StorageEngine {
    base_path: PathBuf,
    db: Connection,
}

/// Lightweight summary returned in list endpoints (no image data).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SnapshotSummary {
    pub id: String,
    pub timestamp: String,
    pub app_name: String,
    pub bundle_id: String,
    pub window_title: String,
    pub text_length: usize,
    pub element_count: usize,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct SnapshotList {
    pub total: usize,
    pub items: Vec<SnapshotSummary>,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct SnapshotQuery {
    pub app_name: Option<String>,
    pub date_from: Option<String>,
    pub date_to: Option<String>,
    pub limit: Option<u32>,
    pub offset: Option<u32>,
}

impl StorageEngine {
    pub fn new(base_path: &Path) -> Result<Self, AppshotError> {
        std::fs::create_dir_all(base_path)?;

        let db_path = base_path.join("index.db");
        let db = Connection::open(&db_path)?;

        // Create table if not exists
        db.execute_batch(
            "CREATE TABLE IF NOT EXISTS snapshots (
                id          TEXT PRIMARY KEY,
                timestamp   TEXT NOT NULL,
                app_name    TEXT NOT NULL,
                bundle_id   TEXT NOT NULL,
                window_title TEXT NOT NULL,
                text_length  INTEGER NOT NULL DEFAULT 0,
                element_count INTEGER NOT NULL DEFAULT 0,
                dir_path    TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_snapshots_timestamp ON snapshots(timestamp DESC);
            CREATE INDEX IF NOT EXISTS idx_snapshots_app_name ON snapshots(app_name);"
        )?;

        Ok(StorageEngine { base_path: base_path.to_path_buf(), db })
    }

    /// Save a raw capture to disk and index it.
    pub fn save(&self, capture: &RawCapture) -> Result<SnapshotSummary, AppshotError> {
        let meta = &capture.metadata;

        // Build directory: base_path/YYYY-MM-DD/AppName-HH-MM-SS/
        let date_dir = &meta.timestamp[..10]; // "2026-05-27"
        let snapshot_dir = self.base_path
            .join(date_dir)
            .join(&meta.id);

        std::fs::create_dir_all(&snapshot_dir)?;

        // Write files
        let png_path = snapshot_dir.join("screenshot.png");
        std::fs::write(&png_path, &capture.png_data)?;

        let ax_path = snapshot_dir.join("accessibility_tree.json");
        let ax_json = serde_json::to_string_pretty(&capture.ax_tree)?;
        std::fs::write(&ax_path, ax_json)?;

        let meta_path = snapshot_dir.join("metadata.json");
        let meta_json = serde_json::to_string_pretty(&capture.metadata)?;
        std::fs::write(&meta_path, meta_json)?;

        // Insert into SQLite index
        self.db.execute(
            "INSERT INTO snapshots (id, timestamp, app_name, bundle_id, window_title,
             text_length, element_count, dir_path)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            rusqlite::params![
                meta.id,
                meta.timestamp,
                meta.app.name,
                meta.app.bundle_id,
                meta.app.window_title,
                meta.accessibility.text_length,
                meta.accessibility.element_count,
                snapshot_dir.to_string_lossy(),
            ],
        )?;

        Ok(SnapshotSummary {
            id: meta.id.clone(),
            timestamp: meta.timestamp.clone(),
            app_name: meta.app.name.clone(),
            bundle_id: meta.app.bundle_id.clone(),
            window_title: meta.app.window_title.clone(),
            text_length: meta.accessibility.text_length,
            element_count: meta.accessibility.element_count,
        })
    }

    /// Query snapshots with optional filters.
    pub fn query(&self, q: &SnapshotQuery) -> Result<SnapshotList, AppshotError> {
        let mut sql = String::from(
            "SELECT id, timestamp, app_name, bundle_id, window_title,
                    text_length, element_count
             FROM snapshots WHERE 1=1"
        );
        let mut params: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(ref app) = q.app_name {
            sql.push_str(&format!(" AND app_name LIKE ?{}", params.len() + 1));
            params.push(Box::new(format!("%{}%", app)));
        }
        if let Some(ref from) = q.date_from {
            sql.push_str(&format!(" AND timestamp >= ?{}", params.len() + 1));
            params.push(Box::new(from.clone()));
        }
        if let Some(ref to) = q.date_to {
            sql.push_str(&format!(" AND timestamp <= ?{}", params.len() + 1));
            params.push(Box::new(format!("{}T23:59:59", to)));
        }

        // Count total
        let count_sql = sql.replacen(
            "SELECT id, timestamp, app_name, bundle_id, window_title, text_length, element_count",
            "SELECT COUNT(*)",
            1,
        );
        let total: usize = self.db.query_row(
            &count_sql,
            rusqlite::params_from_iter(params.iter().map(|p| p.as_ref())),
            |row| row.get(0),
        )?;

        // Fetch page
        sql.push_str(" ORDER BY timestamp DESC");
        let limit = q.limit.unwrap_or(20).min(100);
        let offset = q.offset.unwrap_or(0);
        sql.push_str(&format!(" LIMIT {} OFFSET {}", limit, offset));

        let mut stmt = self.db.prepare(&sql)?;
        let items = stmt.query_map(
            rusqlite::params_from_iter(params.iter().map(|p| p.as_ref())),
            |row| {
                Ok(SnapshotSummary {
                    id: row.get(0)?,
                    timestamp: row.get(1)?,
                    app_name: row.get(2)?,
                    bundle_id: row.get(3)?,
                    window_title: row.get(4)?,
                    text_length: row.get(5)?,
                    element_count: row.get(6)?,
                })
            },
        )?.collect::<Result<Vec<_>, _>>()?;

        Ok(SnapshotList { total, items })
    }

    /// Get a snapshot by ID, including full content.
    pub fn get_full(&self, id: &str) -> Result<Option<SnapshotData>, AppshotError> {
        let dir_path: Option<String> = self.db.query_row(
            "SELECT dir_path FROM snapshots WHERE id = ?1",
            rusqlite::params![id],
            |row| row.get(0),
        ).ok();

        match dir_path {
            Some(dir) => {
                let dir = Path::new(&dir);
                let png_data = std::fs::read(dir.join("screenshot.png"))?;
                let ax_json = std::fs::read_to_string(dir.join("accessibility_tree.json"))?;
                let meta_json = std::fs::read_to_string(dir.join("metadata.json"))?;

                Ok(Some(SnapshotData {
                    png_data,
                    ax_tree_json: ax_json,
                    metadata_json: meta_json,
                }))
            }
            None => Ok(None),
        }
    }

    /// Delete a snapshot by ID (files + index row).
    pub fn delete(&self, id: &str) -> Result<bool, AppshotError> {
        let dir_path: Option<String> = self.db.query_row(
            "SELECT dir_path FROM snapshots WHERE id = ?1",
            rusqlite::params![id],
            |row| row.get(0),
        ).ok();

        if let Some(dir) = dir_path {
            std::fs::remove_dir_all(&dir)?;
            self.db.execute("DELETE FROM snapshots WHERE id = ?1", rusqlite::params![id])?;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Prune snapshots older than N days.
    pub fn prune(&self, older_than_days: u32) -> Result<usize, AppshotError> {
        let cutoff = chrono::Local::now() - chrono::Duration::days(older_than_days as i64);
        let cutoff_str = cutoff.to_rfc3339();

        // Find old snapshots
        let mut stmt = self.db.prepare(
            "SELECT id, dir_path FROM snapshots WHERE timestamp < ?1"
        )?;
        let old: Vec<(String, String)> = stmt.query_map(
            rusqlite::params![cutoff_str],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )?.collect::<Result<Vec<_>, _>>()?;

        let count = old.len();
        for (id, dir) in &old {
            let _ = std::fs::remove_dir_all(dir);
            self.db.execute("DELETE FROM snapshots WHERE id = ?1", rusqlite::params![id])?;
        }

        Ok(count)
    }
}

#[derive(Debug)]
pub struct SnapshotData {
    pub png_data: Vec<u8>,
    pub ax_tree_json: String,
    pub metadata_json: String,
}
