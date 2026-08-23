import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

struct IngestedDocument {
    let document: IndexedDocument
    let chunks: [IndexedChunk]
}

actor DocumentIngestionService {
    private let embeddingService: EmbeddingService
    private let vectorStore: VectorStore

    init(embeddingService: EmbeddingService, vectorStore: VectorStore) {
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
    }

    func ingest(fileURL: URL) async throws {
        let isSecurityScoped = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let extractedText = try extractText(from: fileURL)
        let trimmed = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "DocumentIngestion",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "No readable text could be extracted from '\(fileURL.lastPathComponent)'."]
            )
        }

        let ext = fileURL.pathExtension.lowercased()
        let sourceType = UTType(filenameExtension: ext)?.identifier ?? "public.\(ext.isEmpty ? "data" : ext)"

        let document = IndexedDocument(
            name: fileURL.lastPathComponent,
            sourceType: sourceType
        )

        let chunks = await buildChunks(documentID: document.id, text: trimmed)
        guard !chunks.isEmpty else {
            throw NSError(
                domain: "DocumentIngestion",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "No text chunks generated for '\(fileURL.lastPathComponent)'."]
            )
        }

        try await vectorStore.upsert(document: document, chunks: chunks)
    }

    private func buildChunks(documentID: UUID, text: String, maxChunkLength: Int = 900, overlap: Int = 180) async -> [IndexedChunk] {
        let clean = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !clean.isEmpty else { return [] }

        var chunks: [String] = []
        var start = clean.startIndex

        while start < clean.endIndex {
            let end = clean.index(start, offsetBy: maxChunkLength, limitedBy: clean.endIndex) ?? clean.endIndex
            chunks.append(String(clean[start..<end]))
            guard end < clean.endIndex else { break }
            let overlapStart = clean.index(end, offsetBy: -min(overlap, clean.distance(from: clean.startIndex, to: end)))
            start = overlapStart
        }

        var indexed: [IndexedChunk] = []
        for chunk in chunks where !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let embedding = await embeddingService.embed(text: chunk)
            indexed.append(IndexedChunk(documentID: documentID, text: chunk, embedding: embedding))
        }
        return indexed
    }

    private func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)

        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "json", "csv", "tsv", "swift", "py",
            "c", "cpp", "h", "hpp", "m", "mm", "html", "htm", "xml", "log", "yaml", "yml", "rtf"
        ]

        if textExtensions.contains(ext) || type?.conforms(to: .plainText) == true || type?.conforms(to: .text) == true {
            return try readTextFile(url: url)
        }

        if ext == "pdf" || type?.conforms(to: .pdf) == true {
            return try extractPDFText(url)
        }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "bmp", "webp"]
        if imageExtensions.contains(ext) || type?.conforms(to: .image) == true {
            return try extractImageText(url)
        }

        if ext == "docx" || ext == "doc" || type?.identifier.contains("word") == true {
            throw NSError(
                domain: "DocumentIngestion",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "DOCX format is not supported directly. Please export to PDF or TXT first."]
            )
        }

        // Fallback: Attempt plain text read
        if let fallbackText = try? readTextFile(url: url), !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallbackText
        }

        throw NSError(
            domain: "DocumentIngestion",
            code: 1000,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported file type '.\(ext)'. Please use TXT, MD, PDF, or images."]
        )
    }

    private func readTextFile(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let str = String(data: data, encoding: .utf8) {
            return str
        }
        if let str = String(data: data, encoding: .isoLatin1) {
            return str
        }
        if let str = String(data: data, encoding: .ascii) {
            return str
        }
        if let str = String(data: data, encoding: .utf16) {
            return str
        }
        throw NSError(
            domain: "DocumentIngestion",
            code: 1004,
            userInfo: [NSLocalizedDescriptionKey: "Unable to decode text from '\(url.lastPathComponent)'."]
        )
    }

    private func extractPDFText(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw NSError(
                domain: "DocumentIngestion",
                code: 1005,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF document '\(url.lastPathComponent)'."]
            )
        }

        var output: [String] = []
        var hasText = false

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.append(text)
                hasText = true
            }
        }

        if hasText {
            return output.joined(separator: "\n\n")
        }

        // If no embedded text in PDF (e.g. scanned PDF), OCR rendered page images
        var ocrOutput: [String] = []
        for pageIndex in 0..<min(document.pageCount, 20) {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(pageRect)
                ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }

            if let cgImage = image.cgImage {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                let pageObservations = request.results ?? []
                let pageRecognized = pageObservations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                if !pageRecognized.isEmpty {
                    ocrOutput.append(pageRecognized)
                }
            }
        }

        return ocrOutput.joined(separator: "\n\n")
    }

    private func extractImageText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(data: data, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
