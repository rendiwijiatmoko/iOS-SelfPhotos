import SwiftUI

struct AlbumsListView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: AlbumListViewModel?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Albums")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if let vm {
                            Button(action: { vm.showCreateSheet = true }) {
                                Image(systemName: "plus")
                            }
                        }
                    }
                }
                .sheet(isPresented: Binding(
                    get: { vm?.showCreateSheet ?? false },
                    set: { vm?.showCreateSheet = $0 }
                )) {
                    if let vm {
                        CreateAlbumSheet(vm: vm)
                    }
                }
        }
        .task {
            if vm == nil {
                let api = APIClient(session: session)
                let repo = AlbumRepository(api: api)
                vm = AlbumListViewModel(repo: repo)
            }
            await vm?.loadAlbums()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle, .loading:
                ProgressView()

            case .loaded:
                if vm.albums.isEmpty {
                    emptyState(vm)
                } else {
                    albumsList(vm)
                }

            case .failed(let error):
                errorState(error, vm)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func albumsList(_ vm: AlbumListViewModel) -> some View {
        List {
            if !vm.myAlbums.isEmpty {
                Section("My Albums") {
                    ForEach(vm.myAlbums) { album in
                        NavigationLink(value: album) {
                            AlbumRowView(album: album)
                        }
                    }
                    .onDelete { indices in
                        for index in indices {
                            Task {
                                await vm.deleteAlbum(vm.myAlbums[index].id)
                            }
                        }
                    }
                }
            }

            if !vm.sharedAlbums.isEmpty {
                Section("Shared with Me") {
                    ForEach(vm.sharedAlbums) { album in
                        NavigationLink(value: album) {
                            AlbumRowView(album: album)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: AlbumResponseDTO.self) { album in
            AlbumDetailView(album: album)
        }
        .refreshable {
            await vm.loadAlbums()
        }
    }

    @ViewBuilder
    private func emptyState(_ vm: AlbumListViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Albums")
                .font(.headline)
            Text("Create an album to organize your photos")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Create Album") {
                vm.showCreateSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(_ error: String, _ vm: AlbumListViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to Load")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task {
                    await vm.retry()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AlbumRowView: View {
    let album: AlbumResponseDTO

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnailId = album.albumThumbnailAssetId {
                AuthImage(assetId: thumbnailId)
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Image(systemName: "photo.stack")
                    .frame(width: 60, height: 60)
                    .background(.gray.opacity(0.3))
                    .cornerRadius(8)
            }

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

struct CreateAlbumSheet: View {
    let vm: AlbumListViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Album Name", text: .init(
                    get: { vm.createAlbumName },
                    set: { vm.createAlbumName = $0 }
                ))
                .focused($isFocused)
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        vm.showCreateSheet = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        Task {
                            await vm.createAlbum()
                        }
                    }
                    .disabled(vm.createAlbumName.isEmpty)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}

#Preview {
    AlbumsListView()
        .environment(SessionManager())
}
