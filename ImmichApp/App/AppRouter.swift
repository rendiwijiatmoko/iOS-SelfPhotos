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

struct MainTabView: View {
    @Environment(SessionManager.self) private var session

    var body: some View {
        TabView {
            TimelineView()
                .tabItem {
                    Label("Photos", systemImage: "photo")
                }

            AlbumsListView()
                .tabItem {
                    Label("Albums", systemImage: "folder")
                }

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            PeopleView()
                .tabItem {
                    Label("People", systemImage: "person.2")
                }

            MemoriesView()
                .tabItem {
                    Label("Memories", systemImage: "calendar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

struct SettingsView: View {
    @Environment(SessionManager.self) private var session
    @State private var showLogoutAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let user = session.currentUser {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Email", value: user.email)
                    }
                }

                Section {
                    Button("Logout", role: .destructive) {
                        showLogoutAlert = true
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Logout", isPresented: $showLogoutAlert) {
                Button("Logout", role: .destructive) {
                    session.logout()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to logout?")
            }
        }
    }
}
