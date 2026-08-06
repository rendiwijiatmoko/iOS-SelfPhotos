import SwiftUI

/// Sheet pemilih album dengan pencarian.
struct AlbumPickerSheet: View {
    let albums: [AlbumResponseDTO]
    var onSelect: (AlbumResponseDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// Kunci penyimpanannya SENDIRI, bukan berbagi dengan layar Albums.
    ///
    /// Keduanya dipakai untuk hal yang berbeda: di layar Albums pengguna sedang
    /// menjelajah koleksinya, di sini ia sedang mencari satu album untuk
    /// dituju. Urutan yang berguna di satu tempat belum tentu berguna di yang
    /// lain, dan memaksakan satu nilai membuat pilihan di sini diam-diam
    /// mengubah tampilan layar sebelahnya.
    @AppStorage("albumPickerSort") private var sort: AlbumSort = .lastModified
    @State private var showNewAlbum = false
    @Environment(SessionManager.self) private var session

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add to Album")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search Albums")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        AlbumSortMenu(selection: $sort)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showNewAlbum = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showNewAlbum) { newAlbumSheet }
        }
    }

    /// Album baru di sini TANPA pemilih foto.
    ///
    /// Fotonya sudah ditentukan sebelum sheet ini dibuka — itu justru alasan
    /// sheet ini muncul. Album yang baru dibuat langsung diperlakukan seperti
    /// album yang dipilih, jadi fotonya masuk ke sana tanpa langkah tambahan.
    private var newAlbumSheet: some View {
        NewAlbumSheet(allowsAssetSelection: false) { name, description, _ in
            let repo = AlbumRepository(api: APIClient(session: session))
            do {
                let album = try await repo.create(
                    name: name,
                    description: description.isEmpty ? nil : description)
                onSelect(album)
                dismiss()
                return nil
            } catch {
                return (error as? APIError)?.errorDescription
                    ?? String(localized: "Failed to create album")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            ContentUnavailableView(
                query.isEmpty ? "No Albums" : "No Results",
                systemImage: "rectangle.stack",
                description: Text(query.isEmpty
                    ? "Create an album first."
                    : "No album matches “\(query)”."))
        } else {
            List(filtered) { album in
                Button {
                    onSelect(album)
                    dismiss()
                } label: {
                    row(for: album)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func row(for album: AlbumResponseDTO) -> some View {
        HStack(spacing: 12) {
            thumbnail(for: album)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.albumName)
                    .font(.body)
                Text("^[\(album.assetCount) item](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if album.shared {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func thumbnail(for album: AlbumResponseDTO) -> some View {
        AlbumCoverImage(album: album, placeholderFont: .footnote)
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var filtered: [AlbumResponseDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return albums.sorted(by: sort) }
        return albums
            .filter { $0.albumName.localizedCaseInsensitiveContains(trimmed) }
            .sorted(by: sort)
    }
}
