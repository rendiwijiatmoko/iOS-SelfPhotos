import SwiftUI

struct PeopleView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: PeopleListViewModel?
    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("People")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if case .loading = vm?.phase {
                            ProgressView()
                        }
                    }
                }
        }
        .task {
            if vm == nil {
                let api = APIClient(session: session)
                let repo = PeopleRepository(api: api)
                vm = PeopleListViewModel(repo: repo)
            }
            await vm?.loadPeople()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle, .loading:
                ProgressView()

            case .loaded:
                if vm.people.isEmpty {
                    emptyState
                } else {
                    peopleGrid(vm)
                }

            case .failed(let error):
                errorState(error, vm)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func peopleGrid(_ vm: PeopleListViewModel) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(vm.people) { person in
                    NavigationLink(value: person) {
                        VStack(spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                Circle()
                                    .fill(.gray.opacity(0.2))

                                if let thumbnailPath = person.thumbnailPath {
                                    AsyncImage(url: URL(string: thumbnailPath)) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Color.gray.opacity(0.2)
                                    }
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.gray.opacity(0.5))
                                }

                                if person.isHidden {
                                    Image(systemName: "eye.slash.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .padding(4)
                                        .background(Circle().fill(.white))
                                }
                            }
                            .frame(height: 100)
                            .clipShape(Circle())

                            Text(person.name)
                                .font(.subheadline)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .padding(12)
        }
        .navigationDestination(for: PersonDTO.self) { person in
            PersonDetailView(person: person, repo: PeopleRepository(api: APIClient(session: session)))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No People")
                .font(.headline)
            Text("Faces will appear here when detected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(_ error: String, _ vm: PeopleListViewModel) -> some View {
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
                Task { await vm.retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PersonDetailView: View {
    @State var person: PersonDTO
    let repo: PeopleRepository
    @Environment(SessionManager.self) private var session
    @State private var personDetail: PersonDetailDTO?
    @State private var phase: LoadingPhase<Void> = .idle
    @State private var showRenameSheet = false
    @State private var newName = ""
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        content
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Rename") { showRenameSheet = true }
                        Button(person.isHidden ? "Show" : "Hide") {
                            Task { await toggleHidden() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showRenameSheet) {
                RenameSheet(name: $newName, onSave: {
                    Task { await rename() }
                })
            }
            .task {
                await loadDetail()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            ProgressView()

        case .loaded:
            if let detail = personDetail, !detail.assets.isEmpty {
                assetsGrid(detail)
            } else {
                Text("No photos of this person")
                    .foregroundStyle(.secondary)
            }

        case .failed(let error):
            VStack(spacing: 16) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Retry") {
                    Task { await loadDetail() }
                }
            }
        }
    }

    @ViewBuilder
    private func assetsGrid(_ detail: PersonDetailDTO) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(detail.assets) { asset in
                    NavigationLink(value: AssetLite(
                        id: asset.id,
                        isVideo: asset.isVideo,
                        ratio: 1.0,
                        thumbhash: asset.thumbhash,
                        createdAt: asset.fileCreatedAt
                    )) {
                        AuthImage(assetId: asset.id)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                    }
                }
            }
            .padding(2)
        }
        .navigationDestination(for: AssetLite.self) { asset in
            let allAssets = detail.assets.map { AssetLite(
                id: $0.id,
                isVideo: $0.isVideo,
                ratio: 1.0,
                thumbhash: $0.thumbhash,
                createdAt: $0.fileCreatedAt
            ) }
            AssetDetailView(currentAsset: asset, assets: allAssets)
                .toolbarVisibility(.hidden, for: .tabBar)
        }
    }

    private func loadDetail() async {
        phase = .loading
        do {
            personDetail = try await repo.detail(person.id)
            phase = .loaded(())
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to load"))
        }
    }

    private func rename() async {
        guard !newName.isEmpty else { return }
        do {
            try await repo.rename(person.id, to: newName)
            person.name = newName
            showRenameSheet = false
        } catch {
            // Handle error
        }
    }

    private func toggleHidden() async {
        do {
            try await repo.setHidden(person.id, to: !person.isHidden)
            person.isHidden.toggle()
        } catch {
            // Handle error
        }
    }
}

struct RenameSheet: View {
    @Binding var name: String
    var onSave: () -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($isFocused)
            }
            .navigationTitle("Rename Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

#Preview {
    PeopleView()
        .environment(SessionManager())
}
