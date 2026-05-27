import Foundation
import SQLite3

/// SQLITE_TRANSIENT: tell SQLite to copy the string data.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Storage engine: filesystem for large blobs (PNG, JSON) + SQLite for metadata index.
/// Uses the system SQLite3 (libsqlite3.tbd) — no external dependencies.
final class StorageEngine {

    private let basePath: URL
    private var db: OpaquePointer?

    // MARK: - Init

    init(basePath: String) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let resolved = basePath.replacingOccurrences(of: "~", with: home.path)
        self.basePath = URL(fileURLWithPath: resolved)

        try FileManager.default.createDirectory(at: self.basePath, withIntermediateDirectories: true)

        let dbPath = self.basePath.appendingPathComponent("index.db").path
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw StorageError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }

        try createSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    private func createSchema() throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS snapshots (
                id           TEXT PRIMARY KEY,
                timestamp    TEXT NOT NULL,
                app_name     TEXT NOT NULL,
                bundle_id    TEXT NOT NULL,
                window_title TEXT NOT NULL,
                text_length  INTEGER NOT NULL DEFAULT 0,
                element_count INTEGER NOT NULL DEFAULT 0,
                dir_path     TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_timestamp ON snapshots(timestamp DESC);
            CREATE INDEX IF NOT EXISTS idx_app_name ON snapshots(app_name);
        """
        try exec(sql)
    }

    // MARK: - Save

    @discardableResult
    func save(_ result: CaptureResult) throws -> SnapshotSummary {
        let meta = result.metadata
        let dateDir = String(meta.timestamp.prefix(10))
        let dirName = sanitizeFilename(meta.id)
        let snapDir = basePath
            .appendingPathComponent(dateDir)
            .appendingPathComponent(dirName)

        try FileManager.default.createDirectory(at: snapDir, withIntermediateDirectories: true)

        // Write files
        try result.pngData.write(to: snapDir.appendingPathComponent("screenshot.png"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result.axTree).write(to: snapDir.appendingPathComponent("accessibility_tree.json"))
        try encoder.encode(meta).write(to: snapDir.appendingPathComponent("metadata.json"))

        // Insert into SQLite
        let sql = """
            INSERT OR REPLACE INTO snapshots
            (id, timestamp, app_name, bundle_id, window_title, text_length, element_count, dir_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, meta.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, meta.timestamp, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, meta.app.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, meta.app.bundleID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, meta.app.windowTitle, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 6, Int64(meta.accessibility.textLength))
        sqlite3_bind_int64(stmt, 7, Int64(meta.accessibility.elementCount))
        sqlite3_bind_text(stmt, 8, snapDir.path, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StorageError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }

        return SnapshotSummary(
            id: result.summary.id,
            timestamp: result.summary.timestamp,
            appName: result.summary.appName,
            bundleID: result.summary.bundleID,
            windowTitle: result.summary.windowTitle,
            textPreview: result.summary.textPreview,
            textLength: result.summary.textLength,
            elementCount: result.summary.elementCount,
            dirPath: snapDir.path
        )
    }

    // MARK: - Query

    func list(
        appName: String? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        limit: Int = 20,
        offset: Int = 0
    ) throws -> SnapshotListResponse {
        var sql = "SELECT id, timestamp, app_name, bundle_id, window_title, text_length, element_count, dir_path FROM snapshots"
        var conditions: [String] = []

        if let app = appName { conditions.append("app_name LIKE '%\(app)%'") }
        if let from = dateFrom { conditions.append("timestamp >= '\(from)'") }
        if let to = dateTo { conditions.append("timestamp <= '\(to)T23:59:59'") }

        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }

        // Count total
        let countSQL = sql.replacingOccurrences(
            of: "SELECT id, timestamp, app_name, bundle_id, window_title, text_length, element_count, dir_path",
            with: "SELECT COUNT(*)"
        )
        var countStmt: OpaquePointer?
        sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil)
        defer { sqlite3_finalize(countStmt) }
        var total = 0
        if sqlite3_step(countStmt) == SQLITE_ROW {
            total = Int(sqlite3_column_int64(countStmt, 0))
        }

        // Fetch page
        sql += " ORDER BY timestamp DESC LIMIT \(min(limit, 100)) OFFSET \(offset)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StorageError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var items: [SnapshotSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let ts = String(cString: sqlite3_column_text(stmt, 1))
            let app = String(cString: sqlite3_column_text(stmt, 2))
            let bid = String(cString: sqlite3_column_text(stmt, 3))
            let title = String(cString: sqlite3_column_text(stmt, 4))
            let tlen = Int(sqlite3_column_int64(stmt, 5))
            let ecount = Int(sqlite3_column_int64(stmt, 6))
            let dirPath = String(cString: sqlite3_column_text(stmt, 7))

            // Try to read AX tree for preview
            var preview = ""
            let axFile = URL(fileURLWithPath: dirPath).appendingPathComponent("accessibility_tree.json")
            if let data = try? Data(contentsOf: axFile),
               let tree = try? JSONDecoder().decode(AXNode.self, from: data) {
                preview = String(tree.flattenText().prefix(500))
            }

            items.append(SnapshotSummary(
                id: id, timestamp: ts, appName: app, bundleID: bid,
                windowTitle: title, textPreview: preview,
                textLength: tlen, elementCount: ecount
            ))
        }

        return SnapshotListResponse(total: total, items: items)
    }

    // MARK: - Get Full

    func getFull(id: String) throws -> SnapshotFullResponse? {
        let sql = "SELECT dir_path FROM snapshots WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let dirPath = String(cString: sqlite3_column_text(stmt, 0))
        let dir = URL(fileURLWithPath: dirPath)

        let pngData = try Data(contentsOf: dir.appendingPathComponent("screenshot.png"))
        let axData = try Data(contentsOf: dir.appendingPathComponent("accessibility_tree.json"))
        let metaData = try Data(contentsOf: dir.appendingPathComponent("metadata.json"))

        let axTree = try JSONDecoder().decode(AXNode.self, from: axData)
        let metadata = try JSONDecoder().decode(SnapshotMetadata.self, from: metaData)

        return SnapshotFullResponse(
            metadata: metadata,
            imageBase64: pngData.base64EncodedString(),
            axTree: axTree,
            fullText: axTree.flattenText()
        )
    }

    func getScreenshot(id: String) throws -> Data? {
        let sql = "SELECT dir_path FROM snapshots WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let dirPath = String(cString: sqlite3_column_text(stmt, 0))
        return try Data(contentsOf: URL(fileURLWithPath: dirPath).appendingPathComponent("screenshot.png"))
    }

    // MARK: - Delete

    @discardableResult
    func delete(id: String) throws -> Bool {
        let querySQL = "SELECT dir_path FROM snapshots WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
        let dirPath = String(cString: sqlite3_column_text(stmt, 0))
        try? FileManager.default.removeItem(atPath: dirPath)

        try exec("DELETE FROM snapshots WHERE id = '\(id)'")
        return true
    }

    @discardableResult
    func prune(olderThanDays: Int) throws -> Int {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date()) else { return 0 }
        let cutoffStr = ISO8601DateFormatter().string(from: cutoff)

        let querySQL = "SELECT id, dir_path FROM snapshots WHERE timestamp < '\(cutoffStr)'"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }

        var deleted = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let dirPath = String(cString: sqlite3_column_text(stmt, 1))
            try? FileManager.default.removeItem(atPath: dirPath)
            try exec("DELETE FROM snapshots WHERE id = '\(id)'")
            deleted += 1
        }
        return deleted
    }

    // MARK: - Helpers

    private func exec(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw StorageError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
    }
}

enum StorageError: Error, LocalizedError {
    case sqliteError(String)

    var errorDescription: String? {
        switch self {
        case .sqliteError(let msg): "SQLite error: \(msg)"
        }
    }
}
