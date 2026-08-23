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
            guard let created = LLM(from: modelURL, template: baseTemplate, maxTokenCount: 4096) else {
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

        let dynamicTemplate: Template
        let fullPrompt: String

        if context.isEmpty {
            // No RAG context — simple chat mode
            let systemPrompt = "You are a helpful assistant. Answer concisely."
            switch modelID {
            case "qwen2-0.5b-gguf":
                dynamicTemplate = .chatML(systemPrompt)
                fullPrompt = prompt
            case "tinyllama-gguf":
                dynamicTemplate = .llama(systemPrompt)
                fullPrompt = prompt
            case "gemma-4-e2b-gguf", "gemma-2-2b-gguf":
                dynamicTemplate = .gemma
                fullPrompt = prompt
            default:
                dynamicTemplate = .chatML(systemPrompt)
                fullPrompt = prompt
            }
        } else {
            // RAG mode — keep everything as compact as possible for tiny models.
            // Budget: ~1500 chars for context, leaving room for question + generation.
            let maxContextChars = 1500
            var contextParts: [String] = []
            var usedChars = 0
            for (i, passage) in context.enumerated() {
                let trimmed = String(passage.prefix(500))
                if usedChars + trimmed.count > maxContextChars { break }
                contextParts.append("[\(i+1)] \(trimmed)")
                usedChars += trimmed.count
            }
            let contextBlock = contextParts.joined(separator: "\n")

            // Embed context directly into the user prompt for maximum compatibility
            // with tiny models. Keep system prompt minimal.
            let ragQuestion = "Context:\n\(contextBlock)\n\nBased on the context above, answer this question: \(prompt)"
            let systemPrompt = "Answer using only the provided context."

            switch modelID {
            case "qwen2-0.5b-gguf":
                dynamicTemplate = .chatML(systemPrompt)
                fullPrompt = ragQuestion
            case "tinyllama-gguf":
                dynamicTemplate = .llama(systemPrompt)
                fullPrompt = ragQuestion
            case "gemma-4-e2b-gguf", "gemma-2-2b-gguf":
                dynamicTemplate = .gemma
                fullPrompt = ragQuestion
            default:
                dynamicTemplate = .chatML(systemPrompt)
                fullPrompt = ragQuestion
            }
        }

        let formattedPrompt = dynamicTemplate.preprocess(fullPrompt, [], .none)
        let rawAnswer = await instance.getCompletion(from: formattedPrompt)

        let cleanedAnswer = cleanOutput(rawAnswer, stopSequence: dynamicTemplate.stopSequence)

        if cleanedAnswer.isEmpty {
            // Show raw output for debugging — helps identify if the model produced
            // output that got stripped by cleanup, or truly produced nothing.
            let preview = rawAnswer.prefix(300)
            if rawAnswer.isEmpty {
                return "[Debug] Das Modell hat keinen Output erzeugt. Der Prompt war möglicherweise zu lang für das Kontextfenster. Versuche ein größeres Modell (z.B. Gemma 2B) oder kürze deine Dokumente."
            } else {
                return "[Debug] Raw model output was stripped by cleanup. Raw preview: \(preview)"
            }
        }

        return cleanedAnswer
    }

    private func cleanOutput(_ text: String, stopSequence: String?) -> String {
        var result = text

        // Remove the stop sequence from the template if present
        if let stopSeq = stopSequence, !stopSeq.isEmpty {
            // Only remove the FIRST occurrence at or near the end
            if let range = result.range(of: stopSeq) {
                result = String(result[..<range.lowerBound])
            }
        }

        // Remove known stop/control tokens — but only exact tokens, not substrings.
        // Use iterative removal to handle tokens that appear multiple times.
        let knownStopTokens = [
            "<end_of_turn>",
            "<start_of_turn>",
            "<|im_end|>",
            "<|im_start|>",
            "<|eot_id|>",
            "<|end_of_text|>",
            "<|endoftext|>",
            "</s>",
            "[INST]",
            "[/INST]"
        ]

        for token in knownStopTokens {
            // Remove all occurrences of the exact token
            result = result.replacingOccurrences(of: token, with: "")
        }

        // Remove any "model" or "assistant" role markers that some models prepend
        let roleMarkers = ["model\n", "assistant\n", "Assistant:\n", "Assistant: "]
        for marker in roleMarkers {
            if result.hasPrefix(marker) {
                result = String(result.dropFirst(marker.count))
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
