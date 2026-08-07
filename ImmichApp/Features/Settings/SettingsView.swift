import SwiftUI

/// Sheet profil & pengaturan, bergaya sheet profil di Photos: kepala besar
/// berisi identitas, lalu daftar pengaturan berkelompok di bawahnya.
///
/// Dipindah keluar dari `AppRouter` — berkas itu tugasnya memilih layar mana yang
/// tampil, bukan menampung salah satunya.
///
/// Daftarnya TIDAK pernah disembunyikan di belakang spinner. Sebagian besar
/// isinya sudah ada di perangkat ini dan bisa dipakai walau servernya mati;
/// penantian hanya digambar di baris yang datanya memang harus ditanyakan ke
/// server.
struct SettingsView: View {
    @Environment(SessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var vm: SettingsViewModel
    @State private var showLogoutAlert = false
    @State private var showChangeServerAlert = false

    /// VM dibuat oleh pemanggilnya, bukan menyusul di `task` layar ini.
    ///
    /// Isinya yang lokal — tema, jumlah kolom — sudah ada sejak frame pertama,
    /// dan membuatnya baru setelah view muncul berarti sheet-nya sempat tampil
    /// kosong setiap kali dibuka.
    init(session: SessionManager) {
        _vm = State(initialValue: SettingsViewModel(
            repo: SettingsRepository(api: APIClient(session: session))))
    }

    var body: some View {
        settingsList
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // Bar dibuat transparan supaya kepalanya terlihat sampai ke belakang
            // tombol tutup, seperti di referensi.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { closeButton }
            // Tiga pekerjaan yang benar-benar tidak saling bergantung, jadi
            // masing-masing berjalan sendiri: yang satu gagal atau lambat tidak
            // menahan dua lainnya.
            .task { await vm.loadServerInfo() }
            .task { await vm.refreshCacheSize() }
            .task { await session.refreshUser() }
            .alert("Sign Out", isPresented: $showLogoutAlert) {
                Button("Sign Out", role: .destructive) { session.logout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Change Server", isPresented: $showChangeServerAlert) {
                Button("Change", role: .destructive) { session.logout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will be logged out and need to enter a new server URL.")
            }
    }

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
        }
    }

    // MARK: - Kepala

    private var header: some View {
        VStack(spacing: 10) {
            ProfileAvatar(style: .header)
            Text(session.currentUser?.name ?? "")
                .font(.title.bold())

            assetCountsLabel

            backupBadge
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    /// "388 Photos, 123 Videos" — satu-satunya bagian kepala yang datang dari
    /// server, jadi hanya bagian ini yang menampilkan penantian. Nama dan
    /// avatarnya sudah dipegang `SessionManager` sejak masuk.
    ///
    /// Kosong kalau hitungannya gagal diambil, supaya tidak ada baris "0 Photos"
    /// yang menyesatkan.
    @ViewBuilder
    private var assetCountsLabel: some View {
        if let counts = assetCounts {
            Text(counts)
                .font(.headline)
        } else if vm.serverPhase.isLoading {
            ProgressView()
                .controlSize(.small)
        }
    }

    /// Jamaknya ditulis sendiri, bukan lewat penanda `^[...](inflect:)`: penanda
    /// itu hanya diterjemahkan kalau string-nya melewati katalog lokalisasi, dan
    /// proyek ini belum punya — hasilnya tampil apa adanya di layar.
    private var assetCounts: String? {
        guard let stats = vm.assetStats else { return nil }
        let photos = stats.images == 1 ? "1 Photo" : "\(stats.images) Photos"
        let videos = stats.videos == 1 ? "1 Video" : "\(stats.videos) Videos"
        return "\(photos), \(videos)"
    }

    /// Menyebut fotonya ADA DI SERVER, bukan mengklaim pencadangan otomatis
    /// sedang berjalan — aplikasi ini belum melakukan itu, dan lencana yang
    /// mengaku begitu akan menyesatkan.
    private var backupBadge: some View {
        Label("Synced to server", systemImage: "icloud.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.fill.tertiary, in: .capsule)
    }

    // MARK: - Daftar

    private var settingsList: some View {
        List {
            Section {
                header
            }
            // Kepala duduk di atas latar, bukan di dalam kartu putih seperti
            // baris pengaturan lainnya.
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            updateSection
            serverErrorSection
            librarySection
            appearanceSection
            storageSection
            cacheSection
            aboutSection
            accountSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
    }

    private var librarySection: some View {
        Section("Library") {
            NavigationLink {
                BackupView()
            } label: {
                Label("Back Up Photos", systemImage: "arrow.up.circle")
            }

            NavigationLink {
                DeviceAlbumsView()
            } label: {
                Label("Device Albums", systemImage: "iphone")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker(selection: Binding(
                get: { vm.selectedTheme },
                set: { vm.updateTheme($0) }
            )) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            } label: {
                Label("Theme", systemImage: "circle.lefthalf.filled")
            }

            Picker(selection: Binding(
                get: { vm.gridColumns },
                set: { vm.updateGridColumns($0) }
            )) {
                Text("2 Columns").tag(2)
                Text("3 Columns").tag(3)
                Text("4 Columns").tag(4)
            } label: {
                Label("Grid Columns", systemImage: "square.grid.3x3")
            }
        }
    }

    /// Baris pembaruan hanya muncul kalau memang ada yang lebih baru — bukan
    /// baris tetap bertuliskan "up to date" yang tidak pernah perlu dibaca.
    @ViewBuilder
    private var updateSection: some View {
        if vm.isUpdateAvailable, let latest = vm.latestVersion {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Server update available")
                            .font(.body.weight(.medium))
                        Text("Version \(latest) has been released.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Color.orange)
                }
            }
        }
    }

    /// Kegagalan server jadi SATU bagian di dalam daftar, bukan layar penuh.
    ///
    /// Yang gagal cuma data servernya; tema, jumlah kolom, pembersihan cache,
    /// dan keluar akun tetap bisa dipakai — dan justru saat sambungannya
    /// bermasalah itulah pengguna datang ke sini untuk menggantinya.
    @ViewBuilder
    private var serverErrorSection: some View {
        if let error = vm.serverPhase.errorMessage {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn’t reach the server", systemImage: "exclamationmark.triangle")
                        .font(.body.weight(.medium))
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") { Task { await vm.loadServerInfo() } }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Settings stored on this device still work.")
            }
        }
    }

    /// Saat masih dimuat, bentuknya sudah sama persis dengan versi terisinya —
    /// bilah kosong dan satu baris keterangan — supaya daftarnya tidak melompat
    /// begitu angkanya datang.
    @ViewBuilder
    private var storageSection: some View {
        if let storage = vm.storage {
            Section("Server Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: storageFraction(storage))
                        .tint(storageTint(storage))

                    Text(storageCaption(storage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } else if vm.serverPhase.isLoading {
            Section("Server Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: 0)

                    Text("Loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Pecahan dihitung dari byte mentah kalau ada, karena `diskUsagePercentage`
    /// tidak selalu dikirim server versi lama.
    private func storageFraction(_ storage: ServerStorageDTO) -> Double {
        if let percentage = storage.diskUsagePercentage {
            return min(max(percentage, 0), 100) / 100
        }
        guard let used = storage.diskUseRaw, let total = storage.diskSizeRaw, total > 0 else {
            return 0
        }
        return min(Double(used) / Double(total), 1)
    }

    private func storageTint(_ storage: ServerStorageDTO) -> Color {
        storageFraction(storage) > 0.9 ? .red : .accentColor
    }

    private func storageCaption(_ storage: ServerStorageDTO) -> String {
        let used = storage.diskUse ?? formatBytes(storage.diskUseRaw ?? 0)
        let total = storage.diskSize ?? formatBytes(storage.diskSizeRaw ?? 0)
        return "\(used) of \(total) used"
    }

    /// Ukurannya dibaca dari disk perangkat ini, jadi barisnya tidak ada
    /// hubungannya dengan sambungan ke server.
    private var cacheSection: some View {
        Section {
            Button {
                Task { await vm.clearCache() }
            } label: {
                LabeledContent {
                    Text(formatBytes(vm.cacheSize))
                } label: {
                    Label("Free Up Space", systemImage: "internaldrive")
                }
            }
            .disabled(vm.cacheSize == 0)
        } footer: {
            Text("Removes cached photos from this device. They stay on the server.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App Version", value: vm.appVersion)

            if let server = vm.serverInfo {
                LabeledContent("Server Version", value: server.version)
            } else if vm.serverPhase.isLoading {
                LabeledContent("Server Version") {
                    ProgressView().controlSize(.small)
                }
            }
            if let latest = vm.latestVersion {
                LabeledContent("Latest Version", value: latest)
            }
            if let url = session.baseURL {
                LabeledContent("Server URL", value: displayURL(url))
                    .lineLimit(1)
            }
        }
    }

    /// `/api` dibuang: itu bagian internal dari alamat, bukan yang diketik
    /// pengguna saat menyambung.
    private func displayURL(_ url: URL) -> String {
        let text = url.absoluteString
        return text.hasSuffix("/api") ? String(text.dropLast(4)) : text
    }

    private var accountSection: some View {
        Section {
            Button("Change Server") { showChangeServerAlert = true }
            Button("Sign Out", role: .destructive) { showLogoutAlert = true }
        } footer: {
            if let email = session.currentUser?.email {
                Text(email)
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
