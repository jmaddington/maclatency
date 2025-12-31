// PingLogger.swift
// AIDEV-NOTE: SQLite-based ping history logging service

import Foundation
import SQLite3

/// Singleton service for logging ping results to SQLite database
final class PingLogger: @unchecked Sendable {
    static let shared = PingLogger()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.maclatency.pinglogger", qos: .utility)

    /// Default retention period in days
    static let defaultRetentionDays = 30
    static let retentionDaysOptions = [7, 14, 30, 60, 90, 180, 365]

    private init() {
        openDatabase()
        createTableIfNeeded()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func getDatabasePath() -> String {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MacLatency", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)

        return appFolder.appendingPathComponent("ping_history.sqlite").path
    }

    private func openDatabase() {
        let path = getDatabasePath()
        if sqlite3_open(path, &db) != SQLITE_OK {
            print("[PINGLOG-OPEN-ERR] Failed to open database at \(path)")
            db = nil
        }
    }

    private func createTableIfNeeded() {
        guard db != nil else { return }

        let createSQL = """
            CREATE TABLE IF NOT EXISTS ping_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                host_id TEXT NOT NULL,
                host_label TEXT NOT NULL,
                host_address TEXT NOT NULL,
                latency_ms REAL,
                status TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_ping_log_timestamp ON ping_log(timestamp);
            CREATE INDEX IF NOT EXISTS idx_ping_log_host_id ON ping_log(host_id);
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
            if let err = errMsg {
                print("[PINGLOG-CREATE-ERR] \(String(cString: err))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Logging

    /// Log a batch of readings to the database
    func logReadings(_ readings: [LatencyReading]) {
        guard db != nil else { return }

        queue.async { [weak self] in
            self?.insertReadings(readings)
        }
    }

    private func insertReadings(_ readings: [LatencyReading]) {
        guard db != nil else { return }

        let insertSQL = """
            INSERT INTO ping_log (timestamp, host_id, host_label, host_address, latency_ms, status)
            VALUES (?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            print("[PINGLOG-PREP-ERR] Failed to prepare insert statement")
            return
        }

        defer { sqlite3_finalize(stmt) }

        // Use transaction for batch insert
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

        for reading in readings {
            sqlite3_reset(stmt)

            let timestamp = reading.timestamp.timeIntervalSince1970
            let hostId = reading.hostId.uuidString
            let hostLabel = reading.hostLabel
            let hostAddress = reading.hostAddress
            let status = reading.status.rawValue

            sqlite3_bind_double(stmt, 1, timestamp)
            sqlite3_bind_text(stmt, 2, hostId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 3, hostLabel, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 4, hostAddress, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            if let latencyMs = reading.latencyMs {
                sqlite3_bind_double(stmt, 5, latencyMs)
            } else {
                sqlite3_bind_null(stmt, 5)
            }

            sqlite3_bind_text(stmt, 6, status, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[PINGLOG-INSERT-ERR] Failed to insert reading")
            }
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    // MARK: - Cleanup

    /// Delete records older than the specified number of days
    func cleanupOldRecords(olderThanDays days: Int) {
        guard db != nil else { return }

        queue.async { [weak self] in
            self?.performCleanup(days: days)
        }
    }

    private func performCleanup(days: Int) {
        guard db != nil else { return }

        let cutoffTimestamp = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60).timeIntervalSince1970

        let deleteSQL = "DELETE FROM ping_log WHERE timestamp < ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK else {
            print("[PINGLOG-CLEANUP-PREP-ERR] Failed to prepare delete statement")
            return
        }

        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, cutoffTimestamp)

        if sqlite3_step(stmt) == SQLITE_DONE {
            let deletedCount = sqlite3_changes(db)
            if deletedCount > 0 {
                print("[PINGLOG-CLEANUP] Deleted \(deletedCount) old records")
            }
        }

        // Vacuum periodically to reclaim space
        sqlite3_exec(db, "VACUUM", nil, nil, nil)
    }

    // MARK: - Statistics

    /// Get the total number of logged records
    func getRecordCount() -> Int {
        guard db != nil else { return 0 }

        var count = 0
        let sql = "SELECT COUNT(*) FROM ping_log;"

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }

        return count
    }

    /// Get the database file size in bytes
    func getDatabaseSize() -> Int64 {
        let path = getDatabasePath()
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Get the date range of stored records
    func getDateRange() -> (oldest: Date?, newest: Date?) {
        guard db != nil else { return (nil, nil) }

        var oldest: Date?
        var newest: Date?

        let sql = "SELECT MIN(timestamp), MAX(timestamp) FROM ping_log;"

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                    oldest = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
                }
                if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                    newest = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
                }
            }
            sqlite3_finalize(stmt)
        }

        return (oldest, newest)
    }

    /// Delete all records
    func deleteAllRecords() {
        guard db != nil else { return }

        queue.async { [weak self] in
            guard let self = self, self.db != nil else { return }
            sqlite3_exec(self.db, "DELETE FROM ping_log; VACUUM;", nil, nil, nil)
            print("[PINGLOG-CLEAR] All records deleted")
        }
    }
}
