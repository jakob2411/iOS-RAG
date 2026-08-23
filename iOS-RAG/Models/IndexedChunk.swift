import Foundation

struct IndexedChunk: Identifiable, Codable, Hashable {
    let id: UUID
    let documentID: UUID
    let text: String
    let embedding: [Float]

    init(id: UUID = UUID(), documentID: UUID, text: String, embedding: [Float]) {
        self.id = id
        self.documentID = documentID
        self.text = text
        self.embedding = embedding
    }
}
