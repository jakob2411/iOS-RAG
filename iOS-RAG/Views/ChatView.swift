import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    var onNavigateToModels: (() -> Void)? = nil
    var onOpenGuidedTour: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Menu {
                        if settingsViewModel.installedModels.isEmpty {
                            Text("Kein Modell installiert")
                            Button("Zu den Modellen…") {
                                onNavigateToModels?()
                            }
                        } else {
                            Section("Aktives Modell") {
                                ForEach(settingsViewModel.installedModels) { model in
                                    Button {
                                        Task {
                                            await settingsViewModel.select(modelID: model.id)
                                        }
                                    } label: {
                                        HStack {
                                            Text("\(model.displayName) (\(model.formattedSize))")
                                            if settingsViewModel.selectedModelID == model.id {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            Button("Modelle verwalten…") {
                                onNavigateToModels?()
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "cpu")
                                .font(.caption.weight(.semibold))
                            Text(activeModelDisplayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemBackground))
                        )
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Toggle("RAG", isOn: $viewModel.useRAG)
                            .labelsHidden()
                        Text("RAG")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(viewModel.useRAG ? Color.accentColor : .secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                if viewModel.useRAG {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("RAG aktiv")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.accentColor)
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Embedding: \(activeEmbeddingModelDisplayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.08))
                }

                if settingsViewModel.installedModels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Modell erforderlich")
                                .font(.subheadline.bold())
                            Spacer()
                            Button("Tour") {
                                onOpenGuidedTour?()
                            }
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                        }

                        Text("Um lokal zu chatten, musst du zuerst ein Modell herunterladen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            onNavigateToModels?()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Jetzt Modell herunterladen")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.12))
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }

                if viewModel.messages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "message.badge")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Start a new chat")
                            .font(.headline)
                        Text("Ask anything about your indexed local documents.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            guard let lastID = viewModel.messages.last?.id else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }

                HStack {
                    TextField("Ask about your local data…", text: $viewModel.inputText, axis: .vertical)
                        .lineLimit(1...6)
                        .disabled(viewModel.isSending)

                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        if viewModel.isSending {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                        }
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onOpenGuidedTour?()
                    } label: {
                        Label("Tour", systemImage: "questionmark.circle")
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.showHistory = true
                    } label: {
                        Label("Verlauf", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.startNewSession()
                    } label: {
                        Label("New Session", systemImage: "plus.bubble")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showHistory) {
                ChatHistoryView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadAllSessions()
            }
            .task {
                await settingsViewModel.reload()
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var activeModelDisplayName: String {
        if let selectedID = settingsViewModel.selectedModelID,
           let model = settingsViewModel.installedModels.first(where: { $0.id == selectedID }) {
            return model.displayName
        } else if let first = settingsViewModel.installedModels.first {
            return first.displayName
        }
        return "Modell wählen"
    }

    private var activeEmbeddingModelDisplayName: String {
        if let saved = UserDefaults.standard.string(forKey: "selected_embedding_model"),
           let model = EmbeddingModelType(rawValue: saved) {
            return model.displayName
        }
        return EmbeddingModelType.appleNL.displayName
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    private var bubbleColor: Color {
        switch message.role {
        case .user:
            return .accentColor
        case .assistant:
            return Color(.secondarySystemBackground)
        case .system:
            return Color.orange.opacity(0.18)
        }
    }

    private var textColor: Color {
        isUser ? .white : .primary
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 42) }

            Text(message.text)
                .font(.body)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(bubbleColor)
                )
                .frame(maxWidth: 560, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 42) }
        }
    }
}
