import Foundation

enum ModelRuntime: String, Codable, CaseIterable {
    case coreML
    case ggml
}

struct LocalModel: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let runtime: ModelRuntime
    let remoteURL: URL
    let checksumSHA256: String?
    let filename: String
    let estimatedSizeBytes: Int64

    var formattedSize: String {
        let gb = Double(estimatedSizeBytes) / 1_000_000_000.0
        if gb < 1.0 {
            let mb = Double(estimatedSizeBytes) / 1_000_000.0
            return String(format: "ca. %.2f GB (%.0f MB)", gb, mb)
        } else {
            return String(format: "ca. %.2f GB", gb)
        }
    }

    var sizeInGB: String {
        let gb = Double(estimatedSizeBytes) / 1_000_000_000.0
        return String(format: "%.2f GB", gb)
    }

    var downloadDescription: String {
        "\(displayName) (\(runtime.rawValue), \(formattedSize))"
    }
}
