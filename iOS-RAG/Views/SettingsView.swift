import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    var onOpenGuidedTour: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onOpenGuidedTour?()
                    } label: {
                        Label("Guided Tour & Anleitung", systemImage: "sparkles.rectangle.stack")
                            .font(.body.weight(.medium))
                    }
                }

                Section("Model Catalog") {
                    ForEach(viewModel.catalog) { model in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.displayName)
                                        .font(.body.weight(.medium))
                                    HStack(spacing: 8) {
                                        Text(model.runtime.rawValue.uppercased())
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))

                                        Label(model.formattedSize, systemImage: "internaldrive")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if viewModel.selectedModelID == model.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }

                            HStack {
                                let isInstalled = viewModel.installedModels.contains(where: { $0.id == model.id })
                                Button(isInstalled ? "Downloaded" : "Download") {
                                    Task { await viewModel.download(modelID: model.id) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(viewModel.isDownloading || isInstalled)

                                Button("Use") {
                                    Task { await viewModel.select(modelID: model.id) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    viewModel.isDownloading ||
                                    !viewModel.installedModels.contains(where: { $0.id == model.id })
                                )

                                if viewModel.installedModels.contains(where: { $0.id == model.id }) {
                                    Button("Remove", role: .destructive) {
                                        Task { await viewModel.remove(modelID: model.id) }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(viewModel.isDownloading)
                                }
                            }

                            if viewModel.downloadingModelID == model.id, let downloadProgress = viewModel.downloadProgress {
                                HStack(spacing: 10) {
                                    ProgressView(value: downloadProgress)
                                    Text("\(Int(downloadProgress * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Installed") {
                    if viewModel.installedModels.isEmpty {
                        Text("No models downloaded")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.installedModels, id: \.id) { model in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName)
                                    .font(.body.weight(.medium))
                                Label(model.formattedSize, systemImage: "internaldrive")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.reload()
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
