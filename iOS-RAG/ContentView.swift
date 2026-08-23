import SwiftUI

enum AppTab: Int, Hashable {
    case chat = 0
    case knowledge = 1
    case models = 2
}

struct ContentView: View {
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var indexViewModel: IndexViewModel
    @StateObject private var settingsViewModel: SettingsViewModel

    @State private var selectedTab: AppTab = .chat
    @AppStorage("hasSeenGuidedTour") private var hasSeenGuidedTour = false
    @State private var showingGuidedTour = false

    init(container: AppContainer) {
        _chatViewModel = StateObject(wrappedValue: container.chatViewModel)
        _indexViewModel = StateObject(wrappedValue: container.indexViewModel)
        _settingsViewModel = StateObject(wrappedValue: container.settingsViewModel)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView(
                viewModel: chatViewModel,
                settingsViewModel: settingsViewModel,
                onNavigateToModels: { selectedTab = .models },
                onOpenGuidedTour: { showingGuidedTour = true }
            )
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(AppTab.chat)

            IndexManagerView(viewModel: indexViewModel)
                .tabItem {
                    Label("Knowledge", systemImage: "books.vertical")
                }
                .tag(AppTab.knowledge)

            SettingsView(
                viewModel: settingsViewModel,
                onOpenGuidedTour: { showingGuidedTour = true }
            )
            .tabItem {
                Label("Models", systemImage: "slider.horizontal.3")
            }
            .tag(AppTab.models)
        }
        .tint(.accentColor)
        .sheet(isPresented: $showingGuidedTour) {
            GuidedTourView {
                selectedTab = .models
            }
        }
        .task {
            if !hasSeenGuidedTour {
                showingGuidedTour = true
                hasSeenGuidedTour = true
            }
        }
    }
}
