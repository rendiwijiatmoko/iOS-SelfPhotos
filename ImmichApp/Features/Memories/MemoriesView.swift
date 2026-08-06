import SwiftUI

/// Semua kenangan hari ini, satu kartu per tahun.
///
/// Baris di Library hanya memuat sebagian; layar ini yang memuat semuanya.
struct MemoriesView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: MemoriesViewModel?
    @State private var openedStoryID: String?

    var body: some View {
        content
            .navigationTitle("On This Day")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: openedStoryBinding) { storyCover }
            .task {
                if vm == nil {
                    let api = APIClient(session: session)
                    vm = MemoriesViewModel(
                        repo: MemoriesRepository(api: api),
                        assetRepo: AssetDetailRepository(api: api))
                }
                // Dimuat SEKALI, bukan tiap `task` berjalan.
                //
                // `fullScreenCover` melepas layar ini dari hierarki selama story
                // tampil, jadi menutup story menjalankan `task` lagi. Tanpa
                // penjaga ini, kembali dari story berarti spinner layar penuh
                // dan satu permintaan `/memories` baru — tiap kali.
                if vm?.phase.isIdle == true { await vm?.loadMemories() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded:
                if vm.stories.isEmpty {
                    emptyState
                } else {
                    grid(vm.stories)
                }

            case .failed(let error):
                errorState(error, vm)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func grid(_ stories: [MemoryStory]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                spacing: 12
            ) {
                ForEach(stories) { story in
                    // Lebarnya diserahkan ke kolom grid; kartu selebar 180
                    // tetap akan meluber di layar sempit.
                    MemoryCard(story: story, width: nil) { openedStoryID = story.id }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var storyCover: some View {
        if let vm, let openedStoryID {
            MemoryStoryView(
                stories: vm.stories,
                initialStoryID: openedStoryID,
                prepareShare: { await vm.shareURL(for: $0) })
        }
    }

    private var openedStoryBinding: Binding<Bool> {
        Binding(
            get: { openedStoryID != nil },
            set: { if !$0 { openedStoryID = nil } })
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Memories", systemImage: "sparkles")
        } description: {
            Text("Photos from this day in previous years will show up here.")
        }
    }

    private func errorState(_ error: String, _ vm: MemoriesViewModel) -> some View {
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
