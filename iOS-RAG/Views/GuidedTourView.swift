import SwiftUI

struct GuidedTourView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelectModelsTab: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 16)

                        Text("Willkommen bei iOS-RAG")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        Text("Lokale KI & Privates RAG (Retrieval-Augmented Generation) direkt auf deinem Gerät.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // Steps
                    VStack(spacing: 16) {
                        TourStepCard(
                            stepNumber: "1",
                            badge: "Wichtigster Schritt",
                            badgeColor: .orange,
                            title: "Modell herunterladen",
                            description: "Bevor du den Chat nutzen kannst, musst du im Reiter **Models** ein lokales KI-Modell herunterladen (z. B. Qwen2 0.5B [ca. 0,40 GB], TinyLlama 1.1B [ca. 0,67 GB] oder Gemma 4 E2B [ca. 3,43 GB]). Ohne Modell ist keine lokale Textgenerierung möglich.",
                            icon: "arrow.down.circle.fill",
                            actionTitle: "Jetzt zu den Modellen",
                            action: {
                                dismiss()
                                onSelectModelsTab?()
                            }
                        )

                        TourStepCard(
                            stepNumber: "2",
                            badge: "Sofort aktiv",
                            badgeColor: .blue,
                            title: "Dokumente indexieren",
                            description: "Importiere im Reiter **Knowledge** TXT, Markdown, PDFs oder Bilder. Das integrierte Embedding-Modell (**Apple Natural Language 512d**) ist bereits aktiv und berechnet semantische Vektoren ohne separaten Download.",
                            icon: "books.vertical.fill"
                        )

                        TourStepCard(
                            stepNumber: "3",
                            badge: "100% Privat",
                            badgeColor: .green,
                            title: "Lokal & Offline chatten",
                            description: "Stelle im Reiter **Chat** Fragen zu deinen Dokumenten. Mit dem RAG-Schalter entscheidest du, ob deine Dokumente als Kontext herangezogen werden.",
                            icon: "bubble.left.and.bubble.right.fill"
                        )
                    }
                    .padding(.horizontal, 16)

                    // Footer Action
                    VStack(spacing: 12) {
                        Button {
                            dismiss()
                            onSelectModelsTab?()
                        } label: {
                            Text("1. Modell herunterladen")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Tour schließen") {
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Guided Tour")
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

private struct TourStepCard: View {
    let stepNumber: String
    let badge: String
    let badgeColor: Color
    let title: String
    let description: String
    let icon: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(badgeColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15))
                        .foregroundStyle(badgeColor)
                        .clipShape(Capsule())
                }

                Spacer()
            }

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
