import SwiftUI

struct AlbumsListView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: AlbumListViewModel?
    @State private var scope: Scope = .all
    @Namespace private var albumNamespace
    @State private var editTarget: AlbumResponseDTO?
    @State private var addUserTarget: AlbumResponseDTO?
    @State private var deleteTarget: AlbumResponseDTO?
    @State private var sharedLink: SharedLinkPresentation?
    /// Tata letak & urutan disimpan supaya pilihannya bertahan antar sesi.
    @AppStorage("albumsLayout") private var layout: AlbumLayout = .grid
    @AppStorage("albumsSort") private var sort: AlbumSort = .lastModified

    enum Scope: String, CaseIterable, Identifiable {
        case all, shared, personal
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .shared: "Shared"
            case .personal: "Personal"
            }
        }
    }

    /// Sengaja BUKAN `Layout` — nama itu milik protokol `Layout` di SwiftUI, dan
    /// tipe bersarang akan menaunginya di dalam struct ini.
    enum AlbumLayout: String {
        case grid, list
    }

    var body: some View {
        content
            // Isi SELALU mengisi ruangnya, sebesar apa pun isinya.
            //
            // Bar tepi menempel pada frame view yang dimodifikasinya, bukan pada
            // layar. Selagi memuat, isinya cuma `ProgressView` seukuran ikonnya
            // — jadi segmented ikut menyusut ke tengah bersamanya, lalu melompat
            // ke atas begitu daftar album datang dan isinya membesar.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Albums")
            .navigationBarTitleDisplayMode(.inline)
            // `safeAreaBar`, BUKAN `safeAreaInset`.
            //
            // Keduanya sama-sama menyisihkan ruang, tapi hanya `safeAreaBar`
            // yang memberi tahu scroll view bahwa yang menempel di situ adalah
            // BAR. Itulah yang menyalakan blur bertingkat Liquid Glass di
            // baliknya; `safeAreaInset` cuma ruang kosong, sehingga isi yang
            // lewat di bawahnya terlihat menembus segmented apa adanya.
            .safeAreaBar(edge: .top, spacing: 0) { scopePicker }
            .toolbar { toolbar }
            .sheet(isPresented: createSheetBinding) {
                NewAlbumSheet { name, description, assetIds in
                    await vm?.createAlbum(
                        name: name, description: description, assetIds: assetIds)
                        ?? String(localized: "Failed to create album")
                }
            }
            .sheet(item: $editTarget) { album in
                AlbumEditSheet(album: album) { name, description in
                    Task { await vm?.update(album.id, name: name, description: description) }
                }
            }
            .sheet(item: $addUserTarget) { album in
                AlbumAddUserSheet(album: album) { userIDs in
                    Task { await vm?.addUsers(userIDs, to: album.id) }
                }
            }
            .sheet(item: $sharedLink) { link in
                ShareSheet(url: link.url)
            }
            .confirmationDialog(
                "Delete “\(deleteTarget?.albumName ?? "")”?",
                isPresented: deleteBinding,
                titleVisibility: .visible
            ) {
                Button("Delete Album", role: .destructive) { commitDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The photos will stay in your library.")
            }
            .task { await start() }
    }

    private func start() async {
        if vm == nil {
            let api = APIClient(session: session)
            vm = AlbumListViewModel(repo: AlbumRepository(api: api))
        }
        await vm?.loadAlbums()
    }

    // MARK: - Segmented

    private var scopePicker: some View {
        Picker("Scope", selection: $scope) {
            ForEach(Scope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        // `.segmented` menjembatani ke `UISegmentedControl`. Di iOS 26 yang
        // jadi kaca hanya INDIKATOR pilihannya; track-nya tetap fill solid.
        // Liquid Glass diberikan ke chrome yang dihosting bar — dan itulah
        // sebabnya picker ini dipasang lewat `safeAreaBar`, bukan diberi latar
        // sendiri.
        .pickerStyle(.segmented)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                vm?.showCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .disabled(vm == nil)
        }

        ToolbarItem(placement: .topBarTrailing) { optionsMenu }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Layout", selection: $layout) {
                Label("Grid", systemImage: "square.grid.2x2").tag(AlbumLayout.grid)
                Label("List", systemImage: "list.bullet").tag(AlbumLayout.list)
            }
            .pickerStyle(.inline)

            Picker("Sort By", selection: $sort) {
                ForEach(AlbumSort.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    private var createSheetBinding: Binding<Bool> {
        Binding(
            get: { vm?.showCreateSheet ?? false },
            set: { vm?.showCreateSheet = $0 })
    }

    // confirmationDialog memakai binding Bool, sementara sasarannya perlu
    // disimpan sebagai nilai — jembatannya di sini.
    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } })
    }

    // MARK: - Isi

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle, .loading:
            // Spinner HANYA kalau memang belum ada apa-apa.
            //
            // Potret lokal dibaca di `task`, yaitu setelah render pertama, jadi
            // tanpa gerbang ini layar berkedip spinner satu frame sebelum isi
            // yang sebenarnya sudah tersedia tergambar.
                if vm.albums.isEmpty {
                    ProgressView()
                } else {
                    loadedContent(vm)
                }

            case .loaded:
                loadedContent(vm)

            case .failed(let error):
                errorState(error, vm)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func loadedContent(_ vm: AlbumListViewModel) -> some View {
        let albums = visibleAlbums(vm)

        if albums.isEmpty {
            emptyState(vm)
        } else {
            albumsContainer(albums, vm)
        }
    }

    @ViewBuilder
    private func albumsContainer(
        _ albums: [AlbumResponseDTO],
        _ vm: AlbumListViewModel
    ) -> some View {
        Group {
            switch layout {
            case .grid: albumsGrid(albums)
            case .list: albumsList(albums, vm)
            }
        }
        // `.hard`, bukan `.soft`.
        //
        // `.soft` adalah gradien lembut untuk isi yang memang harus terlihat
        // menembus penuh sampai ke tepi — foto layar penuh, misalnya. Di bawah
        // sebuah bar hasilnya justru yang dikeluhkan: isinya terlihat menembus
        // segmented. `.hard` memberi bidang buram bertepi tegas seukuran
        // bar-nya, sama seperti nav bar dan tab bar bawaan.
        .scrollEdgeEffectStyle(.hard, for: .top)
        .refreshable { await vm.loadAlbums() }
    }

    /// Tautan memakai TUJUAN LANGSUNG, bukan `NavigationLink(value:)` +
    /// `navigationDestination(for:)`.
    ///
    /// Layar ini sendiri sudah didorong ke dalam stack milik Collections.
    /// Mendaftarkan tujuan berbasis nilai dari posisi itu membuat SwiftUI
    /// mendorong dua entri sekaligus — halaman yang sama muncul di atas, dan
    /// detailnya baru terlihat setelah ditekan back. Jalur dari Collections
    /// tidak pernah bermasalah justru karena memakai tujuan langsung.
    private func albumsGrid(_ albums: [AlbumResponseDTO]) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                            .navigationTransition(
                                .zoom(sourceID: album.id, in: albumNamespace))
                    } label: {
                        AlbumGridCard(album: album)
                            .matchedTransitionSource(id: album.id, in: albumNamespace)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        contextMenu(for: album)
                    } preview: {
                        AlbumCoverPreview(album: album, session: session)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private func albumsList(
        _ albums: [AlbumResponseDTO],
        _ vm: AlbumListViewModel
    ) -> some View {
        List {
            ForEach(albums) { album in
                NavigationLink {
                    AlbumDetailView(album: album)
                        .navigationTransition(
                            .zoom(sourceID: album.id, in: albumNamespace))
                } label: {
                    AlbumRowView(album: album)
                        .matchedTransitionSource(id: album.id, in: albumNamespace)
                }
                // Garis pemisah mulai dari tepi kiri TEKS, bukan dari tepi baris:
                // sampul selebar 60 ditambah sela 12. Nilainya relatif terhadap
                // tepi kiri baris ini sendiri.
                .alignmentGuide(.listRowSeparatorLeading) { _ in
                    albumRowThumbnailSide + albumRowSpacing
                }
                .contextMenu {
                    contextMenu(for: album)
                } preview: {
                    AlbumCoverPreview(album: album, session: session)
                }
            }
            .onDelete { indices in
                for index in indices {
                    let id = albums[index].id
                    Task { await vm.deleteAlbum(id) }
                }
            }
            // Garis di ATAS baris pertama dibuang: ia bukan pemisah antar apa
            // pun — di atasnya cuma segmented, yang sudah punya batasnya sendiri.
            .listSectionSeparator(.hidden, edges: .top)
        }
        .listStyle(.plain)
    }

    // MARK: - Context menu

    private func contextMenu(for album: AlbumResponseDTO) -> some View {
        AlbumActionsMenu(
            onEdit: { editTarget = album },
            onAddUser: { addUserTarget = album },
            onCreateLink: { createLink(for: album) },
            onDelete: { deleteTarget = album })
    }

    private func commitDelete() {
        guard let album = deleteTarget else { return }
        Task { await vm?.deleteAlbum(album.id) }
    }

    private func createLink(for album: AlbumResponseDTO) {
        Task {
            sharedLink = await SharedLinkPresentation.create(
                albumId: album.id, session: session)
        }
    }

    // MARK: - Filter & urutan

    private func visibleAlbums(_ vm: AlbumListViewModel) -> [AlbumResponseDTO] {
        let filtered: [AlbumResponseDTO]
        switch scope {
        case .all: filtered = vm.albums
        case .shared: filtered = vm.albums.filter(\.shared)
        case .personal: filtered = vm.albums.filter { !$0.shared }
        }
        return filtered.sorted(by: sort)
    }


    // MARK: - Keadaan kosong & gagal

    private func emptyState(_ vm: AlbumListViewModel) -> some View {
        ContentUnavailableView {
            Label("No Albums", systemImage: "rectangle.stack")
        } description: {
            Text("Create an album to organize your photos.")
        } actions: {
            Button("Create Album") { vm.showCreateSheet = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func errorState(_ error: String, _ vm: AlbumListViewModel) -> some View {
        ContentUnavailableView {
            Label("Failed to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry") { Task { await vm.retry() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Kartu album untuk tata letak grid — sampul penuh dengan nama menumpang di
/// atasnya, mengikuti gaya Albums di Photos.
struct AlbumGridCard: View {
    let album: AlbumResponseDTO

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cover
            caption
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// `Color.clear.overlay` supaya ukuran petaknya ditentukan `aspectRatio` di
    /// luar, bukan oleh gambar di dalamnya.
    private var cover: some View {
        Color.clear.overlay {
            AlbumCoverImage(album: album, placeholderFont: .title)
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(album.albumName)
                .font(.headline)
                .lineLimit(1)
            Text("^[\(album.assetCount) item](inflect: true)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .shadow(radius: 4)
        .padding(12)
    }
}

/// Ukuran sampul dan sela di baris album.
///
/// Konstanta, bukan angka yang ditulis ulang di dua tempat: penjajaran garis
/// pemisah dihitung dari keduanya, dan menyalinnya hanya menunggu keduanya
/// menyimpang.
let albumRowThumbnailSide: CGFloat = 60
let albumRowSpacing: CGFloat = 12

struct AlbumRowView: View {
    let album: AlbumResponseDTO

    var body: some View {
        HStack(spacing: albumRowSpacing) {
            AlbumCoverImage(album: album)
                .frame(width: albumRowThumbnailSide, height: albumRowThumbnailSide)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(album.albumName)
                    .font(.headline)
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.caption)
                    Text("\(album.assetCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if album.shared {
                        Spacer()
                        Image(systemName: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    AlbumsListView()
        .environment(SessionManager())
}
