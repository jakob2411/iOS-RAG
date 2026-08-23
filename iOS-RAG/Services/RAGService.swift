import Foundation

struct RAGResponse {
    let answer: String
    let citations: [String]
}

actor RAGService {
    private let vectorStore: VectorStore
    private let embeddingService: EmbeddingService
    private let runnerFactory: ModelRunnerFactory

    init(vectorStore: VectorStore, embeddingService: EmbeddingService, runnerFactory: ModelRunnerFactory) {
        self.vectorStore = vectorStore
        self.embeddingService = embeddingService
        self.runnerFactory = runnerFactory
    }

    func ask(question: String, useRAG: Bool) async throws -> RAGResponse {
        let runner = try await runnerFactory.activeRunner()
        let context: [String]

        if useRAG {
            let queryEmbedding = await embeddingService.embed(text: question)
            let results = try await vectorStore.search(queryEmbedding: queryEmbedding, k: 2)
            context = results.map(\.text)

            if context.isEmpty {
                // No relevant chunks found – tell the user directly instead of
                // letting the model hallucinate without context.
                return RAGResponse(
                    answer: "Es wurden keine relevanten Passagen in deinen indexierten Dokumenten gefunden. Stelle sicher, dass du Dokumente im Knowledge-Tab indexiert hast und dass das Embedding-Modell seit der Indexierung nicht geändert wurde.",
                    citations: []
                )
            }
        } else {
            context = []
        }

        let answer = try await runner.generate(prompt: question, context: context)
        return RAGResponse(answer: answer, citations: context)
    }
}

