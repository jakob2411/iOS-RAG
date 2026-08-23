import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var catalog: [LocalModel] = []
    @Published var installedModels: [ModelDownloadService.InstalledModel] = []
    @Published var selectedModelID: String?
    @Published var statusMessage: String?
    @Published var isDownloading = false
    @Published var downloadingModelID: String?
    @Published var downloadProgress: Double?

    private let modelDownloadService: ModelDownloadService
    private let runnerFactory: ModelRunnerFactory

    init(modelDownloadService: ModelDownloadService, runnerFactory: ModelRunnerFactory) {
        self.modelDownloadService = modelDownloadService
        self.runnerFactory = runnerFactory
    }

    func reload() async {
        catalog = modelDownloadService.catalog
        selectedModelID = await runnerFactory.selectedModelID()

        do {
            installedModels = try await modelDownloadService.installedModelDetails()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func download(modelID: String) async {
        guard !isDownloading else { return }
        isDownloading = true
        downloadingModelID = modelID
        downloadProgress = 0
        statusMessage = nil
        defer {
            isDownloading = false
            downloadingModelID = nil
            downloadProgress = nil
        }

        do {
            try await modelDownloadService.download(modelID: modelID) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            installedModels = try await modelDownloadService.installedModelDetails()
            await select(modelID: modelID)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func remove(modelID: String) async {
        do {
            try await modelDownloadService.remove(modelID: modelID)
            installedModels = try await modelDownloadService.installedModelDetails()
            if selectedModelID == modelID {
                await runnerFactory.setSelectedModelID("")
                selectedModelID = nil
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func select(modelID: String) async {
        await runnerFactory.setSelectedModelID(modelID)
        selectedModelID = modelID
    }
}
