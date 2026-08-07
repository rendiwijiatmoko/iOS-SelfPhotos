import SwiftUI

struct AppRouter: View {
    @Environment(SessionManager.self) private var session
    @AppStorage(SettingsViewModel.themeKey) private var theme = "system"
    @State private var launch = AppLaunchState.shared
    /// Waktu tunggu maksimum splash.
    ///
    /// Linimasa yang menyalakan tanda "siap", dan tab terakhir yang dipakai bisa
    /// saja bukan Photos — layar itu lalu tidak pernah dibangun dan tandanya
    /// tidak pernah menyala. Batas ini yang memastikan splash selalu berakhir.
    @State private var didTimeOut = false

    var body: some View {
        Group {
            if session.isLoggedIn {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(colorScheme)
        // Splash hanya untuk sesi yang sudah masuk: onboarding tidak membaca
        // cache apa pun, jadi tidak ada yang perlu ditutupi.
        .overlay {
            if session.isLoggedIn, !isReady {
                SplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isReady)
        .task {
            try? await Task.sleep(for: .seconds(2))
            didTimeOut = true
        }
    }

    private var isReady: Bool {
        launch.isReady || didTimeOut
    }

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": .light
        case "dark":  .dark
        default:      nil
        }
    }
}

struct MainTabView: View {
    @Environment(SessionManager.self) private var session
    @State private var syncVM: SyncViewModel?
    @State private var selectedTab: TabID
    @State private var backupNotifier = BackupNotifier.shared
    /// Naik satu setiap tab Photos ditekan ulang saat sudah aktif.
    @State private var photosResetRequest = 0
    /// Layar detail meminta pita offline menyingkir selama ia tampil.
    ///
    /// Singleton, bukan environment — lihat `OfflineBannerSuppression`.
    private var suppression: OfflineBannerSuppression { .shared }

    private static let tabKey = "mainTab.selected"

    /// Sengaja BUKAN bernama `Tab` — nama itu sudah dipakai tipe `Tab` milik
    /// SwiftUI yang dipakai di bawah, dan enum bersarang akan menaunginya.
    private enum TabID: String, Hashable {
        case photos, library, search
    }

    /// Tab terakhir dibaca LANGSUNG di init, bukan lewat `onAppear`.
    ///
    /// Menyetelnya setelah view muncul membuat tab Photos sempat tampil lalu
    /// melompat ke tab tersimpan — terlihat seperti kedipan setiap kali aplikasi
    /// dibuka.
    init() {
        let stored = UserDefaults.standard.string(forKey: Self.tabKey) ?? ""
        _selectedTab = State(initialValue: TabID(rawValue: stored) ?? .photos)
    }

    /// Binding perantara untuk menangkap penekanan tab yang SUDAH aktif.
    ///
    /// `TabView` tidak menyediakan callback untuk itu — setter binding adalah
    /// satu-satunya tempat kejadian tersebut masih terlihat, karena SwiftUI
    /// tetap memanggilnya walau nilainya tidak berubah.
    private var tabSelection: Binding<TabID> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab, newValue == .photos {
                    photosResetRequest += 1
                }
                selectedTab = newValue

                // Search sengaja TIDAK ikut disimpan: tab itu untuk tindakan
                // sesaat, dan membuka aplikasi langsung di kolom pencarian
                // kosong bukan tempat yang berguna untuk memulai.
                guard newValue != .search else { return }
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.tabKey)
            })
    }

    var body: some View {
        // `VStack`, bukan `safeAreaInset`.
        //
        // `safeAreaInset` memang tidak memotong tinggi, tapi harganya lain:
        // pitanya melayang DI ATAS isi yang menembus safe area, dan yang
        // tertutup di situ justru toolbar. VStack membuatnya benar-benar
        // mengambil tempat sendiri, dan itu yang diinginkan.
        VStack(spacing: 0) {
            if let syncVM, !suppression.isSuppressed {
                OfflineBanner(isOnline: syncVM.isOnline)
            }

            TabView(selection: tabSelection) {
                Tab("Photos", systemImage: "photo.on.rectangle.angled", value: TabID.photos) {
                    TimelineView(resetScrollRequest: photosResetRequest)
                }

                Tab("Library", systemImage: "photo.stack", value: TabID.library) {
                    LibraryView()
                }

                // Role .search membuat sistem menempatkannya terpisah di ujung
                // dan mengubahnya jadi kolom cari saat tab-nya dipilih.
                //
                // Kolomnya sendiri dipasang DI DALAM `SearchView`, pada
                // `NavigationStack`-nya — bukan di sini. `searchable` di
                // TabView menyebar ke setiap tab dan memunculkan kolom cari di
                // bar atas Photos dan Library juga.
                Tab(value: TabID.search, role: .search) {
                    SearchView(isActive: selectedTab == .search)
                }
            }
            // Pemberitahuan pencadangan mengantar ke layar Backup, dan layar itu
            // ada DI DALAM tab Library. Yang dikerjakan di sini cuma separuh
            // pertamanya: pindah tab. `LibraryView` yang mendorong layarnya.
            .onChange(of: backupNotifier.shouldSelectLibrary) { _, requested in
                guard requested else { return }
                openBackupTab()
            }
        }
        // Sync disuntikkan ke environment karena linimasa merender DARI hasil
        // sync itu, bukan dari endpoint linimasa. Tanpa akses ke sini, layar
        // Photos tidak punya cara tahu kapan datanya sudah ada.
        .environment(syncVM)
        .task {
            if backupNotifier.shouldSelectLibrary { openBackupTab() }
            // Splash hanya menutupi pembacaan linimasa. Kalau yang terbuka bukan
            // tab Photos, layar itu tidak pernah dibangun dan tidak ada yang
            // perlu ditunggu — tanpa baris ini splash-nya menggantung sampai
            // batas waktunya habis.
            if selectedTab != .photos { AppLaunchState.shared.markReady() }

            if syncVM == nil {
                let api = APIClient(session: session)
                let dataManager = SwiftDataManager.shared
                let repo = SyncRepository(api: api, dataManager: dataManager)
                syncVM = SyncViewModel(repo: repo, dataManager: dataManager)
            }
            await syncVM?.performBackgroundSync()
        }
    }

    private func openBackupTab() {
        selectedTab = .library
        backupNotifier.didSelectLibrary()
    }
}
