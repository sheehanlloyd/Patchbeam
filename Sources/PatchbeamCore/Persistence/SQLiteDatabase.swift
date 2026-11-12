import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal, direct SQLite wrapper (no third-party dependency). Not thread-safe by itself;
/// always owned by an actor (`CapsuleStore`).
final class SQLiteDatabase {
    enum Value {
        case text(String)
        case int(Int64)
        case double(Double)
        case null
    }

    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw PatchbeamError(.persistence, "Could not open the Patchbeam database.", detail: message)
        }
        handle = db
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try execute("PRAGMA busy_timeout=3000;")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw PatchbeamError(.persistence, "Database operation failed.", detail: message)
        }
    }

    @discardableResult
    func run(_ sql: String, _ params: [Value] = []) throws -> Int {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw PatchbeamError(.persistence, "Database write failed.", detail: lastError)
        }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ params: [Value] = []) throws -> [[String: Value]] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var rows: [[String: Value]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw PatchbeamError(.persistence, "Database read failed.", detail: lastError) }
            var row: [String: Value] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row[name] = .int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT: row[name] = .double(sqlite3_column_double(stmt, i))
                case SQLITE_NULL: row[name] = .null
                default: row[name] = .text(String(cString: sqlite3_column_text(stmt, i)))
                }
            }
            rows.append(row)
        }
        return rows
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let value = try body()
            try execute("COMMIT;")
            return value
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private var lastError: String { String(cString: sqlite3_errmsg(handle)) }

    private func prepare(_ sql: String, _ params: [Value]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PatchbeamError(.persistence, "Database statement failed.", detail: lastError)
        }
        for (index, value) in params.enumerated() {
            let i = Int32(index + 1)
            switch value {
            case .text(let s): sqlite3_bind_text(stmt, i, s, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int64(stmt, i, n)
            case .double(let d): sqlite3_bind_double(stmt, i, d)
            case .null: sqlite3_bind_null(stmt, i)
            }
        }
        return stmt
    }
}

extension SQLiteDatabase.Value {
    var string: String? { if case .text(let s) = self { return s }; return nil }
    var int: Int64? { if case .int(let n) = self { return n }; return nil }
}
