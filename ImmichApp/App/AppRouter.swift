import SwiftUI

struct AppRouter: View {
    @Environment(SessionManager.self) private var session

    var body: some View {
        if session.isLoggedIn {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

// Placeholder untuk MainTabView yang akan dibuat di fase berikutnya
struct MainTabView: View {
    var body: some View {
        TabView {
            TimelineView()
                .tabItem {
                    Label("Photos", systemImage: "photo")
                }
            Text("Albums")
                .tabItem {
                    Label("Albums", systemImage: "folder")
                }
            Text("Search")
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            Text("Settings")
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

struct TimelineView: View {
    var body: some View {
        Text("Timeline - Coming in Phase 4")
    }
}

struct OnboardingView: View {
    var body: some View {
        Text("Onboarding - Coming in Phase 3")
    }
}
