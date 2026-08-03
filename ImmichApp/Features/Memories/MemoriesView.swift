import SwiftUI

struct MemoriesView: View {
    @Environment(SessionManager.self) private var session
    @State private var vm: MemoriesViewModel?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Memories")
        }
        .task {
            if vm == nil {
                let api = APIClient(session: session)
                let repo = MemoriesRepository(api: api)
                vm = MemoriesViewModel(repo: repo)
            }
            await vm?.loadMemories()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle, .loading:
                ProgressView()

            case .loaded:
                if vm.memories.isEmpty {
                    emptyState
                } else {
                    memoriesList(vm)
                }

            case .failed(let error):
                errorState(error, vm)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func memoriesList(_ vm: MemoriesViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(vm.memories) { memory in
                    MemoryCardView(memory: memory)
                        .onTapGesture {
                            vm.selectedMemory = memory
                        }
                }
            }
            .padding(12)
        }
        .frame(height: 180)
        .sheet(item: Binding(
            get: { vm.selectedMemory },
            set: { vm.selectedMemory = $0 }
        )) { memory in
            StoryViewer(memory: memory)
                .presentationDetents([.large])
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Memories")
                .font(.headline)
            Text("You'll see your photos from this day in previous years")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(_ error: String, _ vm: MemoriesViewModel) -> some View {
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

struct MemoryCardView: View {
    let memory: MemoryDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let firstAsset = memory.assets.first {
                AuthImage(assetId: firstAsset.id)
                    .frame(height: 120)
                    .clipped()
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(memory.type)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(memory.assets.count) photo\(memory.assets.count != 1 ? "s" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 140)
        .frame(maxHeight: .infinity)
        .background(.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct StoryViewer: View {
    @Environment(\.dismiss) var dismiss
    let memory: MemoryDTO
    @State private var currentIndex = 0
    @State private var autoAdvanceTimer: Timer?
    @State private var isPaused = false
    @State private var showControls = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !memory.assets.isEmpty {
                TabView(selection: $currentIndex) {
                    ForEach(Array(memory.assets.enumerated()), id: \.offset) { index, asset in
                        VStack {
                            AuthImage(assetId: asset.id, size: "preview")
                                .scaledToFit()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                VStack {
                    HStack(spacing: 4) {
                        ForEach(0..<memory.assets.count, id: \.self) { index in
                            Capsule()
                                .fill(index == currentIndex ? Color.white : Color.white.opacity(0.5))
                                .frame(height: 2)
                        }
                    }
                    .padding(12)

                    Spacer()

                    if showControls {
                        HStack {
                            Button {
                                if currentIndex > 0 {
                                    currentIndex -= 1
                                    resetTimer()
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)

                            Text("\(currentIndex + 1) / \(memory.assets.count)")
                                .foregroundStyle(.white)
                                .font(.caption)

                            Button {
                                if currentIndex < memory.assets.count - 1 {
                                    currentIndex += 1
                                    resetTimer()
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(12)
                        .background(.black.opacity(0.6))
                    }
                }
            }
        }
        .onTapGesture {
            withAnimation {
                showControls.toggle()
            }
        }
        .onLongPressGesture(minimumDuration: 0.1, perform: {
            isPaused = true
            autoAdvanceTimer?.invalidate()
        }) { _ in 
            isPaused = false
            startAutoAdvance()
        }
        .onAppear {
            startAutoAdvance()
        }
        .onDisappear {
            autoAdvanceTimer?.invalidate()
        }
    }

    private func startAutoAdvance() {
        autoAdvanceTimer?.invalidate()
        guard !isPaused else { return }

        autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            if currentIndex < memory.assets.count - 1 {
                withAnimation {
                    currentIndex += 1
                }
            } else {
                dismiss()
            }
        }
    }

    private func resetTimer() {
        startAutoAdvance()
    }
}

#Preview {
    MemoriesView()
        .environment(SessionManager())
}
