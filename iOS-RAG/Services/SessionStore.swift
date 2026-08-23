import Foundation

actor SessionStore {
    private let fileManager = FileManager.default
    private let filename = "chat_sessions.json"

    func loadSessions() throws -> [ChatSession] {
        let fileURL = try sessionsFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([ChatSession].self, from: data)
    }

    func save(session: ChatSession) throws {
        var sessions = try loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        let data = try JSONEncoder().encode(sessions)
        try data.write(to: try sessionsFileURL(), options: [.atomic])
    }

    func delete(sessionID: UUID) throws {
        var sessions = try loadSessions()
        sessions.removeAll { $0.id == sessionID }
        let data = try JSONEncoder().encode(sessions)
        try data.write(to: try sessionsFileURL(), options: [.atomic])
    }

    private func sessionsFileURL() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appendingPathComponent(filename)
    }
}
