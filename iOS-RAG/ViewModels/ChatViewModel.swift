import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isSending = false
    @Published var useRAG = true
    @Published var errorMessage: String?

    private let ragService: RAGService
    private let sessionStore: SessionStore
    private var session = ChatSession()

    init(ragService: RAGService, sessionStore: SessionStore) {
        self.ragService = ragService
        self.sessionStore = sessionStore
    }

    func loadSession() async {
        do {
            let savedSessions = try await sessionStore.loadSessions()
            if let first = savedSessions.first {
                session = first
                messages = first.messages
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startNewSession() {
        session = ChatSession()
        messages = []
        inputText = ""
        errorMessage = nil
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        isSending = true
        inputText = ""
        errorMessage = nil

        let user = ChatMessage(role: .user, text: text)
        messages.append(user)

        do {
            let response = try await ragService.ask(question: text, useRAG: useRAG)
            var assistantText = response.answer
            if useRAG, !response.citations.isEmpty {
                assistantText += "\n\nCitations:\n" + response.citations.prefix(3).enumerated().map { "[\($0.offset + 1)] \($0.element.prefix(160))" }.joined(separator: "\n")
            }

            messages.append(ChatMessage(role: .assistant, text: assistantText))
            session.messages = messages
            session.updatedAt = .now
            if session.title == "New Chat" {
                session.title = String(text.prefix(40))
            }
            try await sessionStore.save(session: session)
        } catch {
            errorMessage = error.localizedDescription
            messages.append(ChatMessage(role: .assistant, text: "Failed: \(error.localizedDescription)"))
        }

        isSending = false
    }
}
