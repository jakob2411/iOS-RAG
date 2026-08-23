import Foundation

struct IndexedDocument: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let sourceType: String
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sourceType: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sourceType = sourceType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
