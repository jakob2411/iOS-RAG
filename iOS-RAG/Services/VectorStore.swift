import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor VectorStore {
    private var db: OpaquePointer?

    init(filename: String = "rag.sqlite3") throws {
        let dbURL = try Self.databaseURL(filename: filename)
        db = try Self.openDatabase(url: dbURL)
        try Self.createTablesIfNeeded(db: db)
    }

    deinit {
        sqlite3_close(db)
    }

    func upsert(document: IndexedDocument, chunks: [IndexedChunk]) throws {
        try execute("BEGIN TRANSACTION")
        do {
            try upsertDocument(document)
            try deleteChunks(for: document.id)
            for chunk in chunks {
                try insertChunk(chunk)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func documents() throws -> [IndexedDocument] {
        let sql = """
            SELECT id, name, source_type, created_at, updated_at
            FROM documents
            ORDER BY updated_at DESC;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqlError()
        }

        var result: [IndexedDocument] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let idText = String(cString: sqlite3_column_text(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let source = String(cString: sqlite3_column_text(statement, 2))
            let created = TimeInterval(sqlite3_column_double(statement, 3))
            let updated = TimeInterval(sqlite3_column_double(statement, 4))

            if let id = UUID(uuidString: idText) {
                result.append(
                    IndexedDocument(
                        id: id,
                        name: name,
                        sourceType: source,
                        createdAt: Date(timeIntervalSince1970: created),
                        updatedAt: Date(timeIntervalSince1970: updated)
                    )
                )
            }
        }
        return result
    }

    func delete(documentID: UUID) throws {
        try deleteChunks(for: documentID)
        let sql = "DELETE FROM documents WHERE id = ?;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqlError()
        }

        sqlite3_bind_text(statement, 1, (documentID.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqlError()
        }
    }

    func search(queryEmbedding: [Float], k: Int = 5) throws -> [IndexedChunk] {
        let sql = "SELECT id, document_id, text, embedding_json FROM chunks;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqlError()
        }

        var scored: [(chunk: IndexedChunk, score: Float)] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idC = sqlite3_column_text(statement, 0),
                let docC = sqlite3_column_text(statement, 1),
                let textC = sqlite3_column_text(statement, 2),
                let embC = sqlite3_column_text(statement, 3)
            else {
                continue
            }

            let id = UUID(uuidString: String(cString: idC))
            let doc = UUID(uuidString: String(cString: docC))
            let text = String(cString: textC)
            let embJSON = String(cString: embC)

            guard let id, let doc, let embedding = decodeEmbedding(json: embJSON) else { continue }
            let chunk = IndexedChunk(id: id, documentID: doc, text: text, embedding: embedding)
            scored.append((chunk, cosineSimilarity(queryEmbedding, embedding)))
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(k)
            .map { $0.chunk }
    }

    private func upsertDocument(_ document: IndexedDocument) throws {
        let sql = """
            INSERT INTO documents (id, name, source_type, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              source_type = excluded.source_type,
              updated_at = excluded.updated_at;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqlError()
        }

        sqlite3_bind_text(statement, 1, (document.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (document.name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (document.sourceType as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 4, document.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, document.updatedAt.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqlError()
        }
    }

    private func deleteChunks(for documentID: UUID) throws {
        let sql = "DELETE FROM chunks WHERE document_id = ?;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqlError()
        }

        sqlite3_bind_text(statement, 1, (documentID.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqlError()
        }
    }

    private func insertChunk(_ chunk: IndexedChunk) throws {
        let sql = """
            INSERT INTO chunks (id, document_id, text, embedding_json)
            VALUES (?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqlError()
        }

        sqlite3_bind_text(statement, 1, (chunk.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (chunk.documentID.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (chunk.text as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, (encodeEmbedding(chunk.embedding) as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqlError()
        }
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return -1 }
        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0

        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }

        guard lhsNorm > 0, rhsNorm > 0 else { return -1 }
        return dot / (sqrt(lhsNorm) * sqrt(rhsNorm))
    }

    private func encodeEmbedding(_ embedding: [Float]) -> String {
        guard
            let data = try? JSONEncoder().encode(embedding),
            let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    private func decodeEmbedding(json: String) -> [Float]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([Float].self, from: data)
    }

    private func createTablesIfNeeded() throws {
        let createDocuments = """
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                source_type TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
        """

        let createChunks = """
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                document_id TEXT NOT NULL,
                text TEXT NOT NULL,
                embedding_json TEXT NOT NULL,
                FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE
            );
        """

        try execute(createDocuments)
        try execute(createChunks)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqlError()
        }
    }

    private func sqlError() -> NSError {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
        return NSError(domain: "VectorStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func databaseURL(filename: String) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport.appendingPathComponent(filename)
    }

    private static func openDatabase(url: URL) throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_close(db)
            throw NSError(domain: "VectorStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return db
    }

    private static func createTablesIfNeeded(db: OpaquePointer?) throws {
        let createDocuments = """
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                source_type TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
        """

        let createChunks = """
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                document_id TEXT NOT NULL,
                text TEXT NOT NULL,
                embedding_json TEXT NOT NULL,
                FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE
            );
        """

        try execute(createDocuments, db: db)
        try execute(createChunks, db: db)
    }

    private static func execute(_ sql: String, db: OpaquePointer?) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
            throw NSError(domain: "VectorStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
