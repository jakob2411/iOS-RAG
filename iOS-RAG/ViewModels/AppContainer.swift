import Foundation

@MainActor
final class AppContainer {
    let chatViewModel: ChatViewModel
    let indexViewModel: IndexViewModel
    let settingsViewModel: SettingsViewModel

    private init(chatViewModel: ChatViewModel, indexViewModel: IndexViewModel, settingsViewModel: SettingsViewModel) {
        self.chatViewModel = chatViewModel
        self.indexViewModel = indexViewModel
        self.settingsViewModel = settingsViewModel
    }

    static func makeDefault() async throws -> AppContainer {
        let modelDownloadService = ModelDownloadService()
        let embeddingService = EmbeddingService()
        let vectorStore = try VectorStore()
        let sessionStore = SessionStore()
        let runnerFactory = ModelRunnerFactory(modelDownloadService: modelDownloadService)
        let ragService = RAGService(
            vectorStore: vectorStore,
            embeddingService: embeddingService,
            runnerFactory: runnerFactory
        )
        let ingestionService = DocumentIngestionService(
            embeddingService: embeddingService,
            vectorStore: vectorStore
        )

        let chatVM = ChatViewModel(ragService: ragService, sessionStore: sessionStore)
        let indexVM = IndexViewModel(
            vectorStore: vectorStore,
            ingestionService: ingestionService,
            embeddingService: embeddingService
        )
        let settingsVM = SettingsViewModel(modelDownloadService: modelDownloadService, runnerFactory: runnerFactory)

        await chatVM.loadSession()
        await indexVM.reloadDocuments()
        await settingsVM.reload()

        return AppContainer(chatViewModel: chatVM, indexViewModel: indexVM, settingsViewModel: settingsVM)
    }
}
