import SwiftUI

struct AppRouter: View {
    @Environment(SessionManager.self) private var session
    @AppStorage(SettingsViewModel.themeKey) private var theme = "system"
    @State private var launch = AppLaunchState.shared

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
    }

    private var isReady: Bool {
        launch.isReady
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var syncVM: SyncViewModel?
    @State private var selectedDestination: Destination
    @State private var sidebarAlbumsVM: AlbumListViewModel?
    @State private var showNewAlbum = false
    @State private var backupNotifier = BackupNotifier.shared
    @State private var backupSetupJourney = BackupSetupJourney.shared
    @State private var localPhotoLibrary = LocalPhotoLibrary.shared
    @State private var navigation = AppNavigation.shared
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

    /// Sidebar iPad punya tujuan lebih banyak daripada tab bar iPhone.
    /// ID album disimpan, bukan DTO lengkap, supaya perubahan nama/count tidak
    /// dianggap sebagai tujuan navigasi yang sama sekali baru.
    private enum Destination: Hashable {
        case photos, library, search, allAlbums, album(String), newAlbum
    }

    /// Tab terakhir dibaca LANGSUNG di init, bukan lewat `onAppear`.
    ///
    /// Menyetelnya setelah view muncul membuat tab Photos sempat tampil lalu
    /// melompat ke tab tersimpan — terlihat seperti kedipan setiap kali aplikasi
    /// dibuka.
    init() {
        let stored = UserDefaults.standard.string(forKey: Self.tabKey) ?? ""
        let tab = TabID(rawValue: stored) ?? .photos
        _selectedDestination = State(initialValue: Self.destination(for: tab))
    }

    /// Binding perantara untuk menangkap penekanan tab yang SUDAH aktif.
    ///
    /// `TabView` tidak menyediakan callback untuk itu — setter binding adalah
    /// satu-satunya tempat kejadian tersebut masih terlihat, karena SwiftUI
    /// tetap memanggilnya walau nilainya tidak berubah.
    private var tabSelection: Binding<TabID> {
        Binding(
            get: {
                switch selectedDestination {
                case .photos: .photos
                case .search: .search
                case .library, .allAlbums, .album, .newAlbum: .library
                }
            },
            set: { newValue in
                if selectedDestination == .photos, newValue == .photos {
                    photosResetRequest += 1
                }
                select(Self.destination(for: newValue))
            })
    }

    /// Binding sidebar juga menjadi satu pintu untuk menyimpan tujuan utama.
    /// Album individual diperlakukan sebagai bagian Library saat aplikasi
    /// kembali ke tata letak compact.
    private var sidebarSelection: Binding<Destination> {
        Binding(
            get: { selectedDestination },
            set: { destination in
                if selectedDestination == .photos, destination == .photos {
                    photosResetRequest += 1
                }
                select(destination)
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

            if horizontalSizeClass == .regular {
                sidebarTabView
            } else {
                compactTabView
            }
        }
        // Sync disuntikkan ke environment karena linimasa merender DARI hasil
        // sync itu, bukan dari endpoint linimasa. Tanpa akses ke sini, layar
        // Photos tidak punya cara tahu kapan datanya sudah ada.
        .environment(syncVM)
        .onChange(of: localPhotoLibrary.selectedAlbumIDs) {
            backupSetupJourney.refreshForAlbumSelection()
        }
        .onChange(of: backupNotifier.shouldSelectLibrary) { _, requested in
            guard requested else { return }
            openBackupTab()
        }
        .onChange(of: navigation.pendingDestination) { _, destination in
            guard let destination else { return }
            openExternalDestination(destination)
        }
        .task {
            // Quick action cold-start sudah menunggu sebelum view ini dibuat.
            // Pindahkan tab SEKETIKA, jangan menahannya di belakang sync yang
            // bisa lama atau tidak pernah selesai saat server sedang offline.
            if let destination = navigation.pendingDestination {
                openExternalDestination(destination)
            }
            backupSetupJourney.refreshForAlbumSelection()
            if backupNotifier.shouldSelectLibrary { openBackupTab() }
            // Kalau yang terbuka bukan Photos, tidak ada grid pembuka yang akan
            // mengirim callback siap. Tutup splash langsung untuk tab tersebut.
            if selectedDestination != .photos { AppLaunchState.shared.markReady() }

            if syncVM == nil {
                let api = APIClient(session: session)
                let dataManager = SwiftDataManager.shared
                let repo = SyncRepository(api: api, dataManager: dataManager)
                syncVM = SyncViewModel(repo: repo, dataManager: dataManager)
            }
            // Snapshot widget tidak bergantung pada sync linimasa. Mulai lebih
            // dulu agar album yang baru dipilih dari editor widget mendapat
            // foto tanpa menunggu sinkronisasi perpustakaan besar selesai.
            Task { await WidgetSnapshotExporter.refresh(session: session) }
            await syncVM?.performBackgroundSync()
        }
    }

    /// iPhone dan jendela iPad yang sempit tetap memakai tab bar ringkas.
    private var compactTabView: some View {
        TabView(selection: tabSelection) {
            Tab("Photos", systemImage: "photo.fill.on.rectangle.fill", value: TabID.photos) {
                TimelineView(
                    resetScrollRequest: photosResetRequest,
                    isActive: selectedDestination == .photos)
            }

            Tab(value: TabID.library) {
                LibraryView(isActive: selectedDestination == .library)
            } label: {
                Label(
                    "Library",
                    image: "immiches.tortoise.rectangle.stack.fill"
                )
            }

            // Role .search membuat sistem menempatkannya terpisah di ujung
            // dan mengubahnya jadi kolom cari saat tab-nya dipilih.
            //
            // Kolomnya sendiri dipasang DI DALAM `SearchView`, pada
            // `NavigationStack`-nya — bukan di sini. `searchable` di
            // TabView menyebar ke setiap tab dan memunculkan kolom cari di
            // bar atas Photos dan Library juga.
            Tab(value: TabID.search, role: .search) {
                SearchView(isActive: selectedDestination == .search)
            }
        }
    }

    /// Di lebar regular, gaya ini menjadi sidebar sistem. Kalau jendela iPad
    /// dipersempit SwiftUI dapat merapatkannya, sementara cabang compact di atas
    /// memastikan album dinamis tidak membanjiri tab bar.
    private var sidebarTabView: some View {
        TabView(selection: sidebarSelection) {
            Tab("Photos", systemImage: "photo.on.rectangle.angled", value: Destination.photos) {
                TimelineView(
                    resetScrollRequest: photosResetRequest,
                    isActive: selectedDestination == .photos)
            }

            Tab("Library", systemImage: "photo.stack", value: Destination.library) {
                LibraryView(isActive: selectedDestination == .library)
            }

            TabSection("Albums") {
                Tab(
                    "All Albums",
                    systemImage: "rectangle.stack",
                    value: Destination.allAlbums
                ) {
                    NavigationStack {
                        if let sidebarAlbumsVM {
                            AlbumsListView(viewModel: sidebarAlbumsVM)
                        } else {
                            ProgressView()
                        }
                    }
                }

                if let sidebarAlbumsVM {
                    ForEach(sidebarAlbumsVM.albums) { album in
                        Tab(value: Destination.album(album.id)) {
                            NavigationStack {
                                AlbumDetailView(
                                    album: album,
                                    onContentsChanged: { assets in
                                        sidebarAlbumsVM.applyContents(assets, to: album.id)
                                    },
                                    onDeleted: {
                                        sidebarAlbumsVM.removeDeletedAlbum(album.id)
                                        select(.allAlbums)
                                    })
                            }
                        } label: {
                            // HStack eksplisit, bukan Label. Style sidebar milik
                            // TabView dapat mengambil ukuran intrinsik icon Label
                            // dari rasio foto dan membuat portrait memanjang.
                            HStack(spacing: 10) {
                                SidebarAlbumIcon(album: album)
                                Text(album.albumName)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Tab(
                    "New Album",
                    systemImage: "plus",
                    value: Destination.newAlbum
                ) {
                    EmptyView()
                }
            }

            Tab(value: Destination.search, role: .search) {
                SearchView(isActive: selectedDestination == .search)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sheet(isPresented: $showNewAlbum) {
            NewAlbumSheet { name, description, assetIDs in
                await sidebarAlbumsVM?.createAlbum(
                    name: name,
                    description: description,
                    assetIds: assetIDs)
                    ?? String(localized: "Failed to create album")
            }
        }
        .task {
            if sidebarAlbumsVM == nil {
                let api = APIClient(session: session)
                sidebarAlbumsVM = AlbumListViewModel(repo: AlbumRepository(api: api))
            }
            await sidebarAlbumsVM?.loadAlbums()
        }
    }

    private static func destination(for tab: TabID) -> Destination {
        switch tab {
        case .photos: .photos
        case .library: .library
        case .search: .search
        }
    }

    private func select(_ destination: Destination) {
        // New Album adalah aksi di dalam section, bukan halaman. Jangan ubah
        // selection supaya highlight tetap pada tujuan yang sedang terbuka.
        if destination == .newAlbum {
            guard sidebarAlbumsVM != nil else { return }
            showNewAlbum = true
            return
        }

        selectedDestination = destination

        // Search sengaja TIDAK ikut disimpan: membuka aplikasi langsung di
        // kolom pencarian kosong bukan tempat yang berguna untuk memulai.
        switch destination {
        case .photos:
            UserDefaults.standard.set(TabID.photos.rawValue, forKey: Self.tabKey)
        case .library, .allAlbums, .album:
            UserDefaults.standard.set(TabID.library.rawValue, forKey: Self.tabKey)
        case .search:
            break
        case .newAlbum:
            break
        }
    }

    private func openBackupTab() {
        select(.library)
        backupNotifier.didSelectLibrary()
    }

    /// Search hidup sebagai tab utama; tujuan Library lainnya dibiarkan belum
    /// dikonsumsi agar `LibraryView` dapat mendorong layar detailnya sendiri.
    private func openExternalDestination(_ destination: AppNavigation.Destination) {
        switch destination {
        case .search:
            select(.search)
            navigation.consume(.search)
        case .favorites, .memories, .album:
            select(.library)
        }
    }
}

/// Ikon album khusus sidebar, mengikuti rupa Apple Photos.
///
/// Bidangnya selalu persegi seukuran SF Symbol. Cover dipotong aspect-fill;
/// album tanpa cover memakai simbol foto di atas fill abu-abu rounded.
private struct SidebarAlbumIcon: View {
    let album: AlbumResponseDTO

    @Environment(SessionManager.self) private var session

    private let side: CGFloat = 24
    private let cornerRadius: CGFloat = 5

    var body: some View {
        // Petak dasar menentukan ukuran layout. Cover ditempatkan sebagai
        // overlay supaya rasio intrinsik bitmap tidak dapat meninggikan baris.
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.fill.tertiary)
            .frame(width: side, height: side)
            .overlay {
            if let coverID = AlbumCoverStore.shared.coverID(for: album) {
                AuthImage(
                    assetId: coverID,
                    pixelSize: 64,
                    squareCropPointSize: side)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            // Mencegah style TabView menawarkan ulang ukuran berdasarkan rasio
            // bitmap; ukuran icon harus tetap 24×24 untuk portrait maupun landscape.
            .fixedSize(horizontal: true, vertical: true)
            .task(id: "\(album.id)|\(album.assetCount)|\(album.albumThumbnailAssetId ?? "")") {
                await AlbumCoverStore.shared.resolveCover(for: album, session: session)
            }
    }
}
