import SwiftUI

/// Album perangkat, disusun persis seperti daftar Albums server.
///
/// Yang TIDAK ada di sini: segmented All / Shared / Personal. Album perangkat
/// tidak punya pemiliknya masing-masing dan tidak pernah dibagikan, jadi ketiga
/// pilihan itu akan menyaring sesuatu yang tidak ada bedanya.
///
/// Yang ditampilkan hanya album yang dipilih untuk dicadangkan — sama dengan
/// yang muncul di linimasa. Menampilkan seluruh album perangkat berarti
/// menawarkan isi yang tidak pernah dibaca aplikasi ini.
struct DeviceAlbumsListView: View {
    @State private var library = LocalPhotoLibrary.shared
    @State private var albums: [LocalAlbum] = []
    @State private var isLoading = true
    @Namespace private var albumNamespace
    @AppStorage("deviceAlbumsLayout") private var layout: AlbumsListView.AlbumLayout = .grid
    @AppStorage("deviceAlbumsSort") private var sort: DeviceAlbumSort = .name

    enum DeviceAlbumSort: String, CaseIterable, Identifiable {
        case name, count
        var id: Self { self }

        var label: LocalizedStringKey {
            switch self {
            case .name: "Name"
            case .count: "Item Count"
            }
        }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("On This Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { optionsMenu }
            }
            .task { await load() }
            // Pilihan album diubah dari layar Backup; daftarnya ikut saat kembali.
            .onChange(of: library.selectedAlbumIDs) {
                Task { await load() }
            }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Layout", selection: $layout) {
                Label("Grid", systemImage: "square.grid.2x2")
                    .tag(AlbumsListView.AlbumLayout.grid)
                Label("List", systemImage: "list.bullet")
                    .tag(AlbumsListView.AlbumLayout.list)
            }
            .pickerStyle(.inline)

            Picker("Sort By", selection: $sort) {
                ForEach(DeviceAlbumSort.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    // MARK: - Isi

    @ViewBuilder
    private var content: some View {
        if isLoading && albums.isEmpty {
            ProgressView()
        } else if visibleAlbums.isEmpty {
            emptyState
        } else {
            switch layout {
            case .grid: grid
            case .list: list
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(visibleAlbums) { album in
                    NavigationLink {
                        detail(for: album)
                    } label: {
                        DeviceAlbumGridCard(album: album)
                            .matchedTransitionSource(id: album.id, in: albumNamespace)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private var list: some View {
        List {
            ForEach(visibleAlbums) { album in
                NavigationLink {
                    detail(for: album)
                } label: {
                    DeviceAlbumRowView(album: album)
                        .matchedTransitionSource(id: album.id, in: albumNamespace)
                }
                // Sejajar dengan daftar album server: garis pemisah mulai dari
                // tepi kiri teks, bukan tepi baris.
                .alignmentGuide(.listRowSeparatorLeading) { _ in
                    albumRowThumbnailSide + albumRowSpacing
                }
            }
            .listSectionSeparator(.hidden, edges: .top)
        }
        .listStyle(.plain)
    }

    private func detail(for album: LocalAlbum) -> some View {
        DeviceAlbumDetailView(album: album)
            .navigationTransition(.zoom(sourceID: album.id, in: albumNamespace))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Albums Selected", systemImage: "iphone")
        } description: {
            Text("Choose which albums on this device to include from the Backup screen.")
        }
    }

    // MARK: - Data

    private var visibleAlbums: [LocalAlbum] {
        let selected = albums.filter { library.selectedAlbumIDs.contains($0.id) }
        switch sort {
        case .name:
            return selected.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .count:
            return selected.sorted { $0.count > $1.count }
        }
    }

    private func load() async {
        albums = await library.albums()
        isLoading = false
    }
}

// MARK: - Kartu & baris

/// Kembaran `AlbumGridCard` untuk album perangkat.
///
/// Tidak bisa dipakai ulang begitu saja: yang itu menerima `AlbumResponseDTO`
/// dan mengambil sampulnya lewat jaringan. Yang di sini membaca dari PhotoKit.
/// Yang disamakan tampilannya, bukan tipenya.
struct DeviceAlbumGridCard: View {
    let album: LocalAlbum

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.overlay {
                DeviceAlbumCover(assetID: album.coverAssetID, placeholderFont: .title)
            }
            caption
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(album.title)
                .font(.headline)
                .lineLimit(1)
            Text("^[\(album.count) item](inflect: true)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .shadow(radius: 4)
        .padding(12)
    }
}

struct DeviceAlbumRowView: View {
    let album: LocalAlbum

    var body: some View {
        HStack(spacing: albumRowSpacing) {
            DeviceAlbumCover(assetID: album.coverAssetID, placeholderFont: .body)
                .frame(width: albumRowThumbnailSide, height: albumRowThumbnailSide)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.headline)
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.caption)
                    Text("\(album.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}

/// Sampul album perangkat.
struct DeviceAlbumCover: View {
    let assetID: String?
    var placeholderFont: Font = .body

    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(placeholderFont)
                        .foregroundStyle(.secondary)
                }
            }
            // WAJIB: tanpa ini `scaledToFill` melebar keluar petaknya dan
            // menabrak kartu di sebelahnya.
            .clipped()
            .task(id: assetID) { await loadCover() }
    }

    private func loadCover() async {
        guard let assetID else { return }
        image = await LocalPhotoLibrary.shared.thumbnail(
            for: LocalPhotoLibrary.assetID(for: assetID),
            size: CGSize(width: 600, height: 600))
    }
}
