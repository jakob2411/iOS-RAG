import SwiftUI
import UniformTypeIdentifiers

struct IndexManagerView: View {
    @ObservedObject var viewModel: IndexViewModel
    @State private var showingFileImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section("Embedding Model") {
                    HStack {
                        Text("Modell")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { viewModel.selectedEmbeddingModel },
                            set: { newModel in
                                Task {
                                    await viewModel.setEmbeddingModel(newModel)
                                }
                            }
                        )) {
                            ForEach(EmbeddingModelType.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Aktiv: \(viewModel.selectedEmbeddingModel.displayName)")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                    }

                    Text(viewModel.selectedEmbeddingModel.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Add Documents") {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Add files", systemImage: "plus")
                            .font(.body.weight(.medium))
                    }
                }

                Section("Indexed Documents") {
                    if viewModel.documents.isEmpty {
                        Text("No indexed documents")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.documents) { document in
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.name)
                                Text(document.sourceType)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(documentID: document.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Knowledge")
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.text, .plainText, .pdf, .image, .data],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        await viewModel.index(fileURLs: urls)
                    }
                case .failure(let error):
                    viewModel.statusMessage = error.localizedDescription
                }
            }
            .overlay {
                if viewModel.isIndexing {
                    ProgressView("Indexing…")
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .task {
                await viewModel.reloadDocuments()
            }
            .safeAreaInset(edge: .bottom) {
                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                }
            }
        }
    }
}
