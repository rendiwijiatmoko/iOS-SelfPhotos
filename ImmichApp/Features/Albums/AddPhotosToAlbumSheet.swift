import SwiftUI

/// Pemilih foto untuk ditambahkan ke album.
///
/// Sumbernya `/search/metadata` tanpa filter — endpoint itu sudah
/// mengembalikan aset terbaru lebih dulu, jadi tidak perlu menarik seluruh
/// bucket timeline hanya untuk menampilkan beberapa layar foto.
struct AddPhotosToAlbumSheet: View {
    /// Foto yang sudah ada di album; disembunyikan supaya tidak bisa
    /// ditambahkan dua kali.
    let existingIDs: Set<String>
    let onAdd: ([String]) -> Void

    @Environment(SessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var assets: [AssetLite] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = true

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 3)

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add Photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            onAdd(Array(selectedIDs))
                            dismiss()
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                }
                .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
        } else if assets.isEmpty {
            ContentUnavailableView(
                "No Photos to Add",
                systemImage: "photo.on.rectangle.angled")
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(assets) { asset in
                    Button {
                        toggle(asset)
                    } label: {
                        cell(for: asset)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func cell(for asset: AssetLite) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AuthImage(assetId: asset.id, thumbhash: asset.thumbhash)
                    .opacity(selectedIDs.contains(asset.id) ? 0.6 : 1)
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if selectedIDs.contains(asset.id) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor, in: .circle)
                        .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
    }

    private func toggle(_ asset: AssetLite) {
        if selectedIDs.contains(asset.id) {
            selectedIDs.remove(asset.id)
        } else {
            selectedIDs.insert(asset.id)
        }
    }

    private func load() async {
        guard assets.isEmpty else { return }
        let repo = SearchRepository(api: APIClient(session: session))
        let response = try? await repo.metadataSearch(SearchRequestDTO(size: 200))
        let items = response?.assets.items.map(AssetLite.init) ?? []
        assets = items.filter { !existingIDs.contains($0.id) }
        isLoading = false
    }
}
