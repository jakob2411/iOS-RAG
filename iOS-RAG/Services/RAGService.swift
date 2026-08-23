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
            context = try await vectorStore.search(queryEmbedding: queryEmbedding, k: 4).map(\.text)
        } else {
            context = []
        }

        let answer = try await runner.generate(prompt: question, context: context)
        return RAGResponse(answer: answer, citations: context)
    }
}
