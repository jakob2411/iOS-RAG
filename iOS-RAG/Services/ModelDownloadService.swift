import CryptoKit
import Foundation

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressHandler: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var temporaryFileURL: URL?
    private var response: URLResponse?
    private var hasResumed = false
    private let lock = NSLock()

    init(progressHandler: (@Sendable (Double) -> Void)?) {
        self.progressHandler = progressHandler
    }

    func download(
        session: URLSession,
        request: URLRequest
    ) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: request)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = max(0, min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        progressHandler?(progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        response = downloadTask.response
        let stagingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("model_download_\(UUID().uuidString).tmp")
        do {
            try? FileManager.default.removeItem(at: stagingURL)
            try FileManager.default.moveItem(at: location, to: stagingURL)
            temporaryFileURL = stagingURL
        } catch {
            temporaryFileURL = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true

        if let error {
            continuation?.resume(throwing: error)
            return
        }

        guard let temporaryFileURL, let response else {
            continuation?.resume(
                throwing: NSError(
                    domain: "ModelDownloadService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Download finished without file payload"]
                )
            )
            return
        }

        continuation?.resume(returning: (temporaryFileURL, response))
    }
}

actor ModelDownloadService {
    struct InstalledModel: Identifiable {
        let id: String
        let model: LocalModel
        let localURL: URL
        let fileSizeBytes: Int64
        var displayName: String { model.displayName }
    }

    private let fileManager = FileManager.default

    let catalog: [LocalModel] = [
        LocalModel(
            id: "qwen2-0.5b-gguf",
            displayName: "Qwen2 0.5B Instruct (GGUF)",
            runtime: .ggml,
            remoteURL: URL(string: "https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q4_k_m.gguf")!,
            checksumSHA256: nil,
            filename: "qwen2-0.5b-q4_k_m.gguf"
        ),
        LocalModel(
            id: "tinyllama-gguf",
            displayName: "TinyLlama 1.1B Chat (GGUF)",
            runtime: .ggml,
            remoteURL: URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf")!,
            checksumSHA256: nil,
            filename: "tinyllama-1.1b-chat-v1.0-q4_k_m.gguf"
        ),
        LocalModel(
            id: "gemma-4-e2b-gguf",
            displayName: "Gemma 4 E2B Instruct (GGUF)",
            runtime: .ggml,
            remoteURL: URL(string: "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!,
            checksumSHA256: nil,
            filename: "gemma-4-e2b-it-q4_k_m.gguf"
        )
    ]

    func modelsDirectoryURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("Models", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func installedModels() throws -> [LocalModel] {
        let dir = try modelsDirectoryURL()
        return catalog.filter { fileManager.fileExists(atPath: dir.appendingPathComponent($0.filename).path) }
    }

    func installedModelDetails() throws -> [InstalledModel] {
        let dir = try modelsDirectoryURL()
        return try catalog.compactMap { model in
            let fileURL = dir.appendingPathComponent(model.filename)
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return InstalledModel(id: model.id, model: model, localURL: fileURL, fileSizeBytes: size)
        }
    }

    func download(modelID: String, progressHandler: (@Sendable (Double) -> Void)? = nil) async throws {
        guard let model = catalog.first(where: { $0.id == modelID }) else {
            throw NSError(domain: "ModelDownloadService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Model not found in catalog"])
        }
        let modelsDir = try modelsDirectoryURL()
        let targetURL = modelsDir.appendingPathComponent(model.filename)
        if fileManager.fileExists(atPath: targetURL.path) {
            progressHandler?(1)
            return
        }

        var request = URLRequest(url: model.remoteURL)
        request.timeoutInterval = 60 * 30

        progressHandler?(0)
        let delegate = DownloadProgressDelegate(progressHandler: progressHandler)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (temporaryFileURL, response) = try await delegate.download(session: session, request: request)
        session.finishTasksAndInvalidate()

        defer {
            try? fileManager.removeItem(at: temporaryFileURL)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let serverMessage = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-error-message")
                ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
            throw NSError(
                domain: "ModelDownloadService",
                code: statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed downloading \(model.displayName) (\(statusCode)): \(serverMessage)"
                ]
            )
        }

        try? fileManager.removeItem(at: targetURL)
        try fileManager.moveItem(at: temporaryFileURL, to: targetURL)
        progressHandler?(1)

        if let checksum = model.checksumSHA256 {
            try validateChecksum(of: targetURL, expectedSHA256: checksum)
        }
    }

    func remove(modelID: String) throws {
        guard let model = catalog.first(where: { $0.id == modelID }) else { return }
        let path = try modelsDirectoryURL().appendingPathComponent(model.filename)
        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
    }

    private func validateChecksum(of fileURL: URL, expectedSHA256: String) throws {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        let computed = digest.map { String(format: "%02x", $0) }.joined()
        guard computed.lowercased() == expectedSHA256.lowercased() else {
            throw NSError(domain: "ModelDownloadService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch for downloaded model"])
        }
    }
}
