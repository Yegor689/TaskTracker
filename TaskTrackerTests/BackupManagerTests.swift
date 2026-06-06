import Testing
import Foundation
import SQLite3
@testable import TaskTracker

/// Tests for BackupManager's core, container-independent behavior — the two
/// areas that regressed in v1.0.x: backup-filename date parsing (#13) and
/// capturing a consistent snapshot of a WAL-mode store (#18).
struct BackupManagerTests {

    // MARK: - Filename timestamp parsing (#13)
    //
    // Backups derive their date from the timestamp baked into the filename, not
    // from filesystem creation metadata (copyItem inherits the source store's
    // creation date, which made every backup look equally old).

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return f
    }()

    @Test func parsesTimestampFromAutoStem() throws {
        let date = try #require(BackupManager.date(fromStem: "auto-2026-06-06 14-30-00"))
        #expect(Self.fmt.string(from: date) == "2026-06-06 14-30-00")
    }

    @Test func parsesTimestampFromManualStemWithLabel() throws {
        let date = try #require(BackupManager.date(fromStem: "manual-2026-01-02 09-05-07 before trip"))
        #expect(Self.fmt.string(from: date) == "2026-01-02 09-05-07")
    }

    @Test func parsesTimestampFromPreRestoreStem() throws {
        let date = try #require(BackupManager.date(fromStem: "prerestore-2025-12-31 23-59-59 before restore"))
        #expect(Self.fmt.string(from: date) == "2025-12-31 23-59-59")
    }

    @Test func returnsNilForUnparseableStem() {
        #expect(BackupManager.date(fromStem: "auto-not-a-date") == nil)
        #expect(BackupManager.date(fromStem: "garbage") == nil)
    }

    // MARK: - Online backup produces a complete self-contained snapshot (#18)
    //
    // Exercises the real shipping helper (BackupManager.sqliteOnlineBackup). The
    // store is WAL-mode and held open, so recent writes (completion/priority
    // toggles) live in the -wal, not the base .store; a plain file copy missed
    // them. The online backup must capture the full state. Here we write rows
    // through an OPEN WAL-mode connection (so they're WAL-resident) and confirm
    // the snapshot contains them with exact values.

    @Test func onlineBackupCapturesAllRowsIncludingWALResident() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let src = dir.appendingPathComponent("live.store")
        let dest = dir.appendingPathComponent("backup.store")

        // Populate a WAL-mode DB and keep the connection OPEN so rows are still in
        // the -wal when we snapshot.
        var live: OpaquePointer?
        try #require(sqlite3_open(src.path, &live) == SQLITE_OK)
        defer { sqlite3_close(live) }
        try #require(sqlite3_exec(live, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_exec(live, "PRAGMA wal_autocheckpoint=0;", nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_exec(live, "CREATE TABLE T(id INTEGER PRIMARY KEY, done INT, prio INT);", nil, nil, nil) == SQLITE_OK)
        try #require(sqlite3_exec(live, "INSERT INTO T VALUES (1,1,0),(2,0,2),(3,1,1);", nil, nil, nil) == SQLITE_OK)

        // Snapshot via the real implementation.
        #expect(BackupManager.sqliteOnlineBackup(from: src, to: dest))

        // The snapshot must contain all rows with exact done/prio values. Open
        // read-write (as the app does via ModelContainer) so SQLite can materialize
        // any journal it needs to read the file.
        var verify: OpaquePointer?
        try #require(sqlite3_open_v2(dest.path, &verify, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        defer { sqlite3_close(verify) }
        var stmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(verify, "SELECT COUNT(*), SUM(done), SUM(prio) FROM T;", -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        try #require(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_int(stmt, 0) == 3) // all rows present
        #expect(sqlite3_column_int(stmt, 1) == 2) // completion preserved
        #expect(sqlite3_column_int(stmt, 2) == 3) // priorities preserved
    }
}
