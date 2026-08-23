import Foundation

struct ChatSession: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "New Chat", messages: [ChatMessage] = [], updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
    }
}
