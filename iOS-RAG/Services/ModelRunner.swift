import Foundation
import LLM

protocol LocalModelRunner: Sendable {
    var modelID: String { get }
    var displayName: String { get }
    func generate(prompt: String, context: [String]) async throws -> String
}

actor ModelRunnerFactory {
    private enum Keys {
        static let selectedModelID = "selected_model_id"
    }

    private let modelDownloadService: ModelDownloadService
    private var cachedRunners: [String: GGUFLocalRunner] = [:]

    init(modelDownloadService: ModelDownloadService) {
        self.modelDownloadService = modelDownloadService
    }

    func selectedModelID() -> String? {
        UserDefaults.standard.string(forKey: Keys.selectedModelID)
    }

    func setSelectedModelID(_ modelID: String) {
        UserDefaults.standard.set(modelID, forKey: Keys.selectedModelID)
    }

    func activeRunner() async throws -> LocalModelRunner {
        let installed = try await modelDownloadService.installedModels()
        let preferredID = selectedModelID()

        if let preferredID, let model = installed.first(where: { $0.id == preferredID }) {
            return try await runner(for: model)
        }

        if let first = installed.first {
            return try await runner(for: first)
        }

        return NoModelInstalledRunner()
    }

    private func runner(for model: LocalModel) async throws -> LocalModelRunner {
        if let existing = cachedRunners[model.id] {
            return existing
        }

        let dir = try await modelDownloadService.modelsDirectoryURL()
        let fileURL = dir.appendingPathComponent(model.filename)

        let template: Template
        switch model.id {
        case "qwen2-0.5b-gguf":
            template = .chatML()
        case "tinyllama-gguf":
            template = .llama()
        case "gemma-4-e2b-gguf", "gemma-2-2b-gguf":
            template = .gemma
        default:
            template = .chatML()
        }

        let runner = GGUFLocalRunner(
            modelID: model.id,
            displayName: model.displayName,
            modelURL: fileURL,
            baseTemplate: template
        )
        cachedRunners[model.id] = runner
        return runner
    }
}

actor GGUFLocalRunner: LocalModelRunner {
    let modelID: String
    let displayName: String
    let modelURL: URL
    let baseTemplate: Template

    private var llm: LLM?

    init(modelID: String, displayName: String, modelURL: URL, baseTemplate: Template) {
        self.modelID = modelID
        self.displayName = displayName
        self.modelURL = modelURL
        self.baseTemplate = baseTemplate
    }

    func generate(prompt: String, context: [String]) async throws -> String {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw NSError(
                domain: "GGUFLocalRunner",
                code: 404,
                userInfo: [
                    NSLocalizedDescriptionKey: "Model file for '\(displayName)' not found locally. Please download it from the Models tab."
                ]
            )
        }

        let instance: LLM
        if let existing = llm {
            instance = existing
        } else {
            guard let created = LLM(from: modelURL, template: baseTemplate, maxTokenCount: 2048) else {
                throw NSError(
                    domain: "GGUFLocalRunner",
                    code: 500,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Failed to initialize local LLM engine for '\(displayName)'."
                    ]
                )
            }
            llm = created
            instance = created
        }

        let systemInstructions: String
        if context.isEmpty {
            systemInstructions = "You are a helpful AI assistant. Answer the user prompt accurately and concisely."
        } else {
            let contextContent = context.joined(separator: "\n\n---\n\n")
            systemInstructions = """
            You are a helpful knowledge assistant. Answer the question using ONLY the provided document context. If the answer cannot be found in the context, clearly say that the documents do not provide this information.

            Document Context:
            \(contextContent)
            """
        }

        let dynamicTemplate: Template
        let fullPrompt: String
        switch modelID {
        case "qwen2-0.5b-gguf":
            dynamicTemplate = .chatML(systemInstructions)
            fullPrompt = prompt
        case "tinyllama-gguf":
            dynamicTemplate = .llama(systemInstructions)
            fullPrompt = prompt
        case "gemma-4-e2b-gguf", "gemma-2-2b-gguf":
            dynamicTemplate = .gemma
            fullPrompt = "\(systemInstructions)\n\n\(prompt)"
        default:
            dynamicTemplate = .chatML(systemInstructions)
            fullPrompt = prompt
        }

        let formattedPrompt = dynamicTemplate.preprocess(fullPrompt, [], .none)
        let rawAnswer = await instance.getCompletion(from: formattedPrompt)

        var cleanedAnswer = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stopSeq = dynamicTemplate.stopSequence, cleanedAnswer.hasSuffix(stopSeq) {
            cleanedAnswer = String(cleanedAnswer.dropLast(stopSeq.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleanedAnswer.isEmpty {
            return "I processed your question with the local model, but no text response was produced."
        }

        return cleanedAnswer
    }
}

struct NoModelInstalledRunner: LocalModelRunner {
    let modelID: String = "none"
    let displayName: String = "No Model Downloaded"

    func generate(prompt: String, context: [String]) async throws -> String {
        throw NSError(
            domain: "ModelRunner",
            code: 404,
            userInfo: [
                NSLocalizedDescriptionKey: "No local model downloaded yet. Please open the Models tab and download a model (e.g. Qwen2 or TinyLlama) to start chatting."
            ]
        )
    }
}
