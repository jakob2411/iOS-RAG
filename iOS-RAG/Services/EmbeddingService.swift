import Foundation
import NaturalLanguage

enum EmbeddingModelType: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleNL = "apple_nl"
    case fastHash384 = "fast_hash_384"
    case fastHash768 = "fast_hash_768"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleNL:
            return "Apple Natural Language (512d)"
        case .fastHash384:
            return "Fast Token Hash (384d)"
        case .fastHash768:
            return "High-Dim Token Hash (768d)"
        }
    }

    var description: String {
        switch self {
        case .appleNL:
            return "On-Device Apple ML Embeddings (512d) mit semantischem Sprachverständnis."
        case .fastHash384:
            return "Schnelle, deterministische Token-Hashing-Vektoren (384d)."
        case .fastHash768:
            return "Hochdimensionale Token-Hashing-Vektoren (768d) für detaillierten Wortabgleich."
        }
    }

    var dimension: Int {
        switch self {
        case .appleNL:
            return 512
        case .fastHash384:
            return 384
        case .fastHash768:
            return 768
        }
    }
}

actor EmbeddingService {
    private enum Keys {
        static let selectedEmbeddingModel = "selected_embedding_model"
    }

    private var currentModelType: EmbeddingModelType

    init() {
        if let saved = UserDefaults.standard.string(forKey: Keys.selectedEmbeddingModel),
           let type = EmbeddingModelType(rawValue: saved) {
            self.currentModelType = type
        } else {
            self.currentModelType = .appleNL
        }
    }

    func selectedModelType() -> EmbeddingModelType {
        currentModelType
    }

    func setModelType(_ type: EmbeddingModelType) {
        currentModelType = type
        UserDefaults.standard.set(type.rawValue, forKey: Keys.selectedEmbeddingModel)
    }

    func embed(text: String) async -> [Float] {
        switch currentModelType {
        case .appleNL:
            return embedWithAppleNL(text: text)
        case .fastHash384:
            return embedWithHash(text: text, dimension: 384)
        case .fastHash768:
            return embedWithHash(text: text, dimension: 768)
        }
    }

    private func embedWithAppleNL(text: String) -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(repeating: Float(0), count: 512) }

        let currentLangCode = Locale.current.language.languageCode?.identifier ?? "en"
        let currentLang = NLLanguage(rawValue: currentLangCode)

        let nlEmbedding = NLEmbedding.sentenceEmbedding(for: currentLang)
            ?? NLEmbedding.sentenceEmbedding(for: .german)
            ?? NLEmbedding.sentenceEmbedding(for: .english)

        if let nl = nlEmbedding, let vector = nl.vector(for: trimmed) {
            let floatVec = vector.map { Float($0) }
            return normalize(floatVec)
        }

        if let wordNL = NLEmbedding.wordEmbedding(for: currentLang)
            ?? NLEmbedding.wordEmbedding(for: .german)
            ?? NLEmbedding.wordEmbedding(for: .english) {
            var combined = Array(repeating: Float(0), count: wordNL.dimension)
            var tokenCount = 0
            let tokens = trimmed.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            for token in tokens {
                if let vec = wordNL.vector(for: String(token)) {
                    for i in 0..<min(combined.count, vec.count) {
                        combined[i] += Float(vec[i])
                    }
                    tokenCount += 1
                }
            }
            if tokenCount > 0 {
                return normalize(combined)
            }
        }

        return embedWithHash(text: text, dimension: 512)
    }

    private func embedWithHash(text: String, dimension: Int) -> [Float] {
        var vector = Array(repeating: Float(0), count: dimension)
        let normalized = text.lowercased()
        for token in normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            var hasher = Hasher()
            hasher.combine(String(token))
            let index = abs(hasher.finalize()) % dimension
            vector[index] += 1
        }
        return normalize(vector)
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}
