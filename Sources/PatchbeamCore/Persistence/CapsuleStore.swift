import Foundation

/// Durable, transactional storage for projects, capsules, events and verification records.
/// Typed Codable models are stored as JSON alongside indexed columns. No secrets are stored.
public actor CapsuleStore {
    public static let schemaVersion = 2

    private let db: SQLiteDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteDatabase(path: path.path)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        try Self.migrate(db)
    }

    /// Ordered, idempotent migrations. Never edit a shipped migration; append a new one.
    static let migrations: [String] = [
        // v1
        """
        CREATE TABLE IF NOT EXISTS projects(
          id TEXT PRIMARY KEY, canonical_root TEXT NOT NULL UNIQUE, last_used REAL NOT NULL, json TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS capsules(
          id TEXT PRIMARY KEY, project_id TEXT NOT NULL, status TEXT NOT NULL,
          created_at REAL NOT NULL, updated_at REAL NOT NULL, json TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS capsules_updated ON capsules(updated_at);
        CREATE TABLE IF NOT EXISTS events(
          capsule_id TEXT NOT NULL, sequence INTEGER NOT NULL, timestamp REAL NOT NULL,
          kind TEXT NOT NULL, json TEXT NOT NULL, PRIMARY KEY(capsule_id, sequence));
        CREATE TABLE IF NOT EXISTS verifications(
          id TEXT PRIMARY KEY, capsule_id TEXT NOT NULL, started_at REAL NOT NULL, json TEXT NOT NULL);
        """,
        // v2: audit trail of state transitions
        """
        CREATE TABLE IF NOT EXISTS transitions(
          capsule_id TEXT NOT NULL, at REAL NOT NULL, from_status TEXT NOT NULL, to_status TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS transitions_capsule ON transitions(capsule_id);
        """,
    ]

    private static func migrate(_ db: SQLiteDatabase) throws {
        try db.execute("CREATE TABLE IF NOT EXISTS schema_version(version INTEGER NOT NULL);")
        let current = try db.query("SELECT MAX(version) AS v FROM schema_version").first?["v"]?.int ?? 0
        for (index, sql) in migrations.enumerated() where Int64(index + 1) > current {
            try db.transaction {
                try db.execute(sql)
                try db.run("INSERT INTO schema_version(version) VALUES (?)", [.int(Int64(index + 1))])
            }
        }
    }

    public func schemaVersionInstalled() throws -> Int {
        Int(try db.query("SELECT MAX(version) AS v FROM schema_version").first?["v"]?.int ?? 0)
    }

    // MARK: Projects

    public func upsert(_ project: Project) throws {
        let json = try String(decoding: encoder.encode(project), as: UTF8.self)
        try db.run(
            """
            INSERT INTO projects(id, canonical_root, last_used, json) VALUES (?,?,?,?)
            ON CONFLICT(canonical_root) DO UPDATE SET last_used=excluded.last_used, json=excluded.json
            """,
            [.text(project.id.uuidString), .text(project.canonicalRoot), .double(project.lastUsed.timeIntervalSince1970), .text(json)]
        )
    }

    public func project(root: String) throws -> Project? {
        try db.query("SELECT json FROM projects WHERE canonical_root = ?", [.text(root)]).first?["json"]?.string
            .map { try decoder.decode(Project.self, from: Data($0.utf8)) }
    }

    public func recentProjects(limit: Int = 10) throws -> [Project] {
        try db.query("SELECT json FROM projects ORDER BY last_used DESC LIMIT ?", [.int(Int64(limit))])
            .compactMap { $0["json"]?.string }
            .map { try decoder.decode(Project.self, from: Data($0.utf8)) }
    }

    // MARK: Capsules

    /// Persist a capsule. When `from` is supplied the transition is recorded in the same transaction.
    public func save(_ capsule: Capsule, transitionFrom from: CapsuleStatus? = nil) throws {
        let json = try String(decoding: encoder.encode(capsule), as: UTF8.self)
        try db.transaction {
            try db.run(
                """
                INSERT INTO capsules(id, project_id, status, created_at, updated_at, json) VALUES (?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET status=excluded.status, updated_at=excluded.updated_at, json=excluded.json
                """,
                [.text(capsule.id.uuidString), .text(capsule.projectID.uuidString), .text(capsule.status.rawValue),
                 .double(capsule.createdAt.timeIntervalSince1970), .double(capsule.updatedAt.timeIntervalSince1970), .text(json)]
            )
            if let from, from != capsule.status {
                try db.run(
                    "INSERT INTO transitions(capsule_id, at, from_status, to_status) VALUES (?,?,?,?)",
                    [.text(capsule.id.uuidString), .double(capsule.updatedAt.timeIntervalSince1970), .text(from.rawValue), .text(capsule.status.rawValue)]
                )
            }
        }
    }

    public func capsule(_ id: UUID) throws -> Capsule? {
        try db.query("SELECT json FROM capsules WHERE id = ?", [.text(id.uuidString)]).first?["json"]?.string
            .map { try decoder.decode(Capsule.self, from: Data($0.utf8)) }
    }

    public func allCapsules(limit: Int = 200) throws -> [Capsule] {
        try db.query("SELECT json FROM capsules ORDER BY updated_at DESC LIMIT ?", [.int(Int64(limit))])
            .compactMap { $0["json"]?.string }
            .map { try decoder.decode(Capsule.self, from: Data($0.utf8)) }
    }

    public func transitions(for id: UUID) throws -> [(CapsuleStatus, CapsuleStatus)] {
        try db.query("SELECT from_status, to_status FROM transitions WHERE capsule_id = ? ORDER BY rowid", [.text(id.uuidString)])
            .compactMap { row in
                guard let f = row["from_status"]?.string.flatMap(CapsuleStatus.init(rawValue:)),
                      let t = row["to_status"]?.string.flatMap(CapsuleStatus.init(rawValue:)) else { return nil }
                return (f, t)
            }
    }

    public func deleteCapsule(_ id: UUID) throws {
        try db.transaction {
            for table in ["events", "verifications", "transitions"] {
                try db.run("DELETE FROM \(table) WHERE capsule_id = ?", [.text(id.uuidString)])
            }
            try db.run("DELETE FROM capsules WHERE id = ?", [.text(id.uuidString)])
        }
    }

    /// "Delete All Local History" (PRD §14.2).
    public func deleteAll() throws {
        try db.transaction {
            for table in ["events", "verifications", "transitions", "capsules", "projects"] {
                try db.run("DELETE FROM \(table)")
            }
        }
    }

    // MARK: Events

    /// Insert an event; duplicates (same capsule + sequence) are ignored, keeping ordering stable.
    @discardableResult
    public func append(_ event: AgentEvent) throws -> Bool {
        let json = try String(decoding: encoder.encode(event), as: UTF8.self)
        let changed = try db.run(
            "INSERT OR IGNORE INTO events(capsule_id, sequence, timestamp, kind, json) VALUES (?,?,?,?,?)",
            [.text(event.capsuleID.uuidString), .int(Int64(event.sequence)), .double(event.timestamp.timeIntervalSince1970), .text(event.kind.rawValue), .text(json)]
        )
        return changed > 0
    }

    public func events(for id: UUID) throws -> [AgentEvent] {
        try db.query("SELECT json FROM events WHERE capsule_id = ? ORDER BY sequence", [.text(id.uuidString)])
            .compactMap { $0["json"]?.string }
            .map { try decoder.decode(AgentEvent.self, from: Data($0.utf8)) }
    }

    public func nextSequence(for id: UUID) throws -> Int {
        Int(try db.query("SELECT MAX(sequence) AS s FROM events WHERE capsule_id = ?", [.text(id.uuidString)]).first?["s"]?.int ?? 0) + 1
    }

    // MARK: Verifications

    public func save(_ record: VerificationRecord) throws {
        let json = try String(decoding: encoder.encode(record), as: UTF8.self)
        try db.run(
            "INSERT OR REPLACE INTO verifications(id, capsule_id, started_at, json) VALUES (?,?,?,?)",
            [.text(record.id.uuidString), .text(record.capsuleID.uuidString), .double(record.startedAt.timeIntervalSince1970), .text(json)]
        )
    }

    public func verifications(for id: UUID) throws -> [VerificationRecord] {
        try db.query("SELECT json FROM verifications WHERE capsule_id = ? ORDER BY started_at", [.text(id.uuidString)])
            .compactMap { $0["json"]?.string }
            .map { try decoder.decode(VerificationRecord.self, from: Data($0.utf8)) }
    }
}
