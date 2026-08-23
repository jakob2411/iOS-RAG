import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: ChatRole
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, text: String, timestamp: Date = .now) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}
