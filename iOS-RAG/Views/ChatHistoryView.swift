import SwiftUI

struct ChatHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Kein Verlauf vorhanden")
                            .font(.headline)
                        Text("Deine gespeicherten Chats erscheinen hier.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(viewModel.sessions.sorted(by: { $0.updatedAt > $1.updatedAt })) { session in
                            Button {
                                viewModel.selectSession(session)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    Text(session.updatedAt, style: .relative)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteSession(session)
                                    }
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Verlauf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
}
