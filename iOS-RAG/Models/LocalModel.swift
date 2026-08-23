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

    var downloadDescription: String {
        "\(displayName) (\(runtime.rawValue))"
    }
}
