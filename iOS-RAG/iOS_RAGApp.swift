import SwiftUI

@main
struct iOS_RAGApp: App {
    @StateObject private var bootstrap = AppBootstrapper()

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = bootstrap.container {
                    ContentView(container: container)
                } else if let error = bootstrap.error {
                    VStack(spacing: 12) {
                        Text("Failed to start app")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ProgressView("Preparing local services…")
                        .task {
                            await bootstrap.bootstrapIfNeeded()
                        }
                }
            }
        }
    }
}

@MainActor
final class AppBootstrapper: ObservableObject {
    @Published private(set) var container: AppContainer?
    @Published private(set) var error: String?

    private var isBootstrapping = false

    func bootstrapIfNeeded() async {
        guard !isBootstrapping, container == nil else { return }
        isBootstrapping = true
        do {
            container = try await AppContainer.makeDefault()
        } catch {
            self.error = error.localizedDescription
        }
        isBootstrapping = false
    }
}
