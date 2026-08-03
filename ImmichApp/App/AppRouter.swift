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

            BackupView()
                .tabItem {
                    Label("Backup", systemImage: "arrow.up.circle")
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
    @State private var vm: SettingsViewModel?
    @State private var showLogoutAlert = false
    @State private var showChangeServerAlert = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Settings")
        }
        .task {
            if vm == nil {
                let api = APIClient(session: session)
                let repo = SettingsRepository(api: api)
                vm = SettingsViewModel(repo: repo)
            }
            await vm?.loadSettings()
        }
        .alert("Logout", isPresented: $showLogoutAlert) {
            Button("Logout", role: .destructive) {
                Task {
                    await vm?.logout()
                    session.logout()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .alert("Change Server", isPresented: $showChangeServerAlert) {
            Button("Change", role: .destructive) {
                session.logout()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You will be logged out and need to enter a new server URL.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle, .loading:
                ProgressView()

            case .loaded:
                settingsContent(vm)

            case .failed(let error):
                errorState(error, vm)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func settingsContent(_ vm: SettingsViewModel) -> some View {
        List {
            // Profile Section
            Section("Profile") {
                if let user = vm.user {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(user.name)
                                    .font(.headline)

                                if user.isAdmin == true {
                                    Label("Admin", systemImage: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }

                            Text(user.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            }

            // Storage Section
            if let storage = vm.storage {
                Section("Storage") {
                    LabeledContent("Used", value: formatBytes(storage.diskUse ?? 0))
                    LabeledContent("Total", value: formatBytes(storage.diskSize ?? 0))

                    if let total = storage.diskSize, total > 0 {
                        let used = Double(storage.diskUse ?? 0)
                        let percentage = (used / Double(total)) * 100
                        ProgressView(value: percentage / 100)
                            .tint(percentage > 90 ? .red : .green)
                    }
                }
            }

            // Preferences Section
            Section("Preferences") {
                Picker("Theme", selection: Binding(
                    get: { vm.selectedTheme },
                    set: { theme in
                        Task { await vm.updateTheme(theme) }
                    }
                )) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }

                Picker("Grid Columns", selection: Binding(
                    get: { vm.gridColumns },
                    set: { columns in
                        Task { await vm.updateGridColumns(columns) }
                    }
                )) {
                    Text("2 Columns").tag(2)
                    Text("3 Columns").tag(3)
                    Text("4 Columns").tag(4)
                }
            }

            // Server Section
            if let server = vm.serverInfo {
                Section("Server") {
                    LabeledContent("Version", value: server.version)
                    if let url = session.baseURL {
                        LabeledContent("URL", value: url.absoluteString)
                            .lineLimit(1)
                    }
                }
            }

            // Actions Section
            Section {
                Button("Clear Cache", action: clearCache)
                Button("Change Server", role: .destructive) {
                    showChangeServerAlert = true
                }
                Button("Logout", role: .destructive) {
                    showLogoutAlert = true
                }
            }
        }
    }

    @ViewBuilder
    private func errorState(_ error: String, _ vm: SettingsViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to Load Settings")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await vm.loadSettings() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clearCache() {
        Task {
            await ImageCache.shared.clear()
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
