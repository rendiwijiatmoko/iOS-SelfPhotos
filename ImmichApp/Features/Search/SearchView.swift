import SwiftUI

struct SearchView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: SearchViewModel?
    @State private var showExplore = false
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .searchable(
                    text: Binding(
                        get: { vm?.searchText ?? "" },
                        set: { newText in
                            vm?.searchText = newText
                            if !newText.isEmpty {
                                Task { await vm?.search(newText) }
                            }
                        }
                    ),
                    prompt: "Search photos"
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if vm != nil {
                            Button(action: { showExplore = true }) {
                                Image(systemName: "sparkles")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showExplore) {
                    if let vm {
                        ExploreView(vm: vm)
                    }
                }
        }
        .task {
            if vm == nil {
                let api = APIClient(session: session)
                let repo = SearchRepository(api: api)
                vm = SearchViewModel(repo: repo)
            }
            await vm?.loadSuggestions()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            if vm.searchText.isEmpty {
                suggestionsView(vm)
            } else {
                switch vm.phase {
                case .idle, .loading:
                    ProgressView()

                case .loaded:
                    if vm.results.isEmpty {
                        noResultsState
                    } else {
                        resultsGrid(vm)
                    }

                case .failed(let error):
                    errorState(error, vm)
                }
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func suggestionsView(_ vm: SearchViewModel) -> some View {
        List {
            if !vm.suggestions.isEmpty {
                Section("Popular") {
                    ForEach(vm.suggestions, id: \.self) { suggestion in
                        Button(action: {
                            vm.searchText = suggestion
                            Task { await vm.search(suggestion) }
                        }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                Text(suggestion)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultsGrid(_ vm: SearchViewModel) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(vm.results) { asset in
                    NavigationLink(value: asset) {
                        AuthImage(assetId: asset.id, thumbhash: asset.thumbhash)
                            .aspectRatio(asset.ratio, contentMode: .fill)
                            .clipped()
                    }
                    .onAppear {
                        if vm.results.last?.id == asset.id {
                            Task { await vm.loadMore() }
                        }
                    }
                }
            }
            .padding(2)
        }
        .navigationDestination(for: AssetLite.self) { asset in
            let allAssets = vm.results
            AssetDetailView(currentAsset: asset, assets: allAssets)
                .toolbarVisibility(.hidden, for: .tabBar)
        }
    }

    @ViewBuilder
    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Results")
                .font(.headline)
            Text("Try different keywords")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(_ error: String, _ vm: SearchViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Search Failed")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await vm.search(vm.searchText) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ExploreView: View {
    let vm: SearchViewModel

    var body: some View {
        NavigationStack {
            Text("Explore - Coming Soon")
                .navigationTitle("Explore")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SearchView()
        .environment(SessionManager())
}
