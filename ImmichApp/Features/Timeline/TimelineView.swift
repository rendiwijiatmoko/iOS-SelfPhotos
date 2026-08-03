import SwiftUI

struct TimelineView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: TimelineViewModel?
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Photos")
                .navigationDestination(for: AssetLite.self) { asset in
                    AssetDetailView(asset: asset)
                }
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
                let repo = TimelineRepository(api: api)
                vm = TimelineViewModel(repo: repo)
            }
            await vm?.loadBuckets()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle, .loading:
                ProgressView()

            case .loaded:
                if vm.sections.isEmpty {
                    emptyState
                } else {
                    timelineGrid(vm)
                }

            case .failed(let error):
                errorState(error, vm)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func timelineGrid(_ vm: TimelineViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
                ForEach(vm.sections) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(section.assets) { asset in
                                NavigationLink(value: asset) {
                                    AuthImage(assetId: asset.id)
                                        .aspectRatio(asset.ratio, contentMode: .fill)
                                        .clipped()
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    } header: {
                        Text(section.title)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(.bar)
                            .task {
                                await vm.loadSectionIfNeeded(section.id)
                            }
                    }
                }
            }
        }
        .refreshable {
            await vm.loadBuckets()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Photos")
                .font(.headline)
            Text("Upload photos to see them here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    @ViewBuilder
    private func errorState(_ error: String, _ vm: TimelineViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to Load")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task {
                    await vm.retry()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

#Preview {
    TimelineView()
        .environment(SessionManager())
}
