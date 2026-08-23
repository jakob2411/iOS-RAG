import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isSending = false
    @Published var useRAG = true
    @Published var errorMessage: String?

    @Published var sessions: [ChatSession] = []
    @Published var showHistory = false

    private let ragService: RAGService
    private let sessionStore: SessionStore
    private var session = ChatSession()

    init(ragService: RAGService, sessionStore: SessionStore) {
        self.ragService = ragService
        self.sessionStore = sessionStore
    }

    func loadAllSessions() async {
        do {
            sessions = try await sessionStore.loadSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSession() async {
        await loadAllSessions()
        if let first = sessions.first {
            session = first
            messages = first.messages
        }
    }

    func selectSession(_ selectedSession: ChatSession) {
        session = selectedSession
        messages = selectedSession.messages
        showHistory = false
    }

    func deleteSession(_ sessionToDelete: ChatSession) async {
        do {
            try await sessionStore.delete(sessionID: sessionToDelete.id)
            await loadAllSessions()
            if session.id == sessionToDelete.id {
                startNewSession()
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
        Task {
            await loadAllSessions()
        }
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
            await loadAllSessions()
        } catch {
            errorMessage = error.localizedDescription
            messages.append(ChatMessage(role: .assistant, text: "Failed: \(error.localizedDescription)"))
        }

        isSending = false
    }
}
