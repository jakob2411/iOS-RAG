import Foundation

@MainActor
final class IndexViewModel: ObservableObject {
    @Published var documents: [IndexedDocument] = []
    @Published var statusMessage: String?
    @Published var isIndexing = false
    @Published var selectedEmbeddingModel: EmbeddingModelType = .appleNL

    private let vectorStore: VectorStore
    private let ingestionService: DocumentIngestionService
    private let embeddingService: EmbeddingService

    init(vectorStore: VectorStore, ingestionService: DocumentIngestionService, embeddingService: EmbeddingService) {
        self.vectorStore = vectorStore
        self.ingestionService = ingestionService
        self.embeddingService = embeddingService
    }

    func loadSettings() async {
        selectedEmbeddingModel = await embeddingService.selectedModelType()
    }

    func setEmbeddingModel(_ model: EmbeddingModelType) async {
        selectedEmbeddingModel = model
        await embeddingService.setModelType(model)
        statusMessage = "Embedding model set to \(model.displayName)."
    }

    func reloadDocuments() async {
        await loadSettings()
        do {
            documents = try await vectorStore.documents()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func index(fileURL: URL) async {
        await index(fileURLs: [fileURL])
    }

    func index(fileURLs: [URL]) async {
        guard !isIndexing, !fileURLs.isEmpty else { return }
        isIndexing = true
        statusMessage = "Indexing \(fileURLs.count) document(s)..."
        defer { isIndexing = false }

        var successCount = 0
        var errors: [String] = []

        for url in fileURLs {
            do {
                try await ingestionService.ingest(fileURL: url)
                successCount += 1
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        await reloadDocuments()

        if errors.isEmpty {
            statusMessage = "Indexed \(successCount) document(s) successfully."
        } else if successCount > 0 {
            statusMessage = "Indexed \(successCount) file(s). Errors: \(errors.joined(separator: "; "))"
        } else {
            statusMessage = "Failed indexing: \(errors.joined(separator: "; "))"
        }
    }

    func delete(documentID: UUID) async {
        do {
            try await vectorStore.delete(documentID: documentID)
            await reloadDocuments()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
