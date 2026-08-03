import SwiftUI

struct AssetDetailView: View {
    @State var currentAsset: AssetLite
    let assets: [AssetLite]

    @Environment(SessionManager.self) private var session
    @State private var vm: AssetDetailViewModel?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var isSharePresented = false
    @State private var downloadedFileURL: URL?
    @State private var showToolbar = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentAsset) {
                ForEach(assets) { asset in
                    VStack {
                        ZoomableImageView(assetId: asset.id, thumbhash: asset.thumbhash, scale: $scale, offset: $offset)
                    }
                    .tag(asset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                HStack {
                    if showToolbar {
                        Text("\(currentAssetIndex + 1) / \(assets.count)")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.6))
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(16)

                Spacer()

                if showToolbar && !assets.isEmpty {
                    PreviewIndicator(
                        assets: assets,
                        currentAsset: $currentAsset,
                        onSelect: { asset in
                            currentAsset = asset
                            resetZoom()
                        }
                    )
                    .background(.black.opacity(0.7))
                }
            }
        }
        .onTapGesture {
            withAnimation {
                showToolbar.toggle()
            }
        }
        .sheet(isPresented: Binding(
            get: { vm?.showInfoPanel ?? false },
            set: { vm?.showInfoPanel = $0 }
        )) {
            if let detail = vm?.detail {
                InfoPanel(detail: detail)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $isSharePresented) {
            if let url = downloadedFileURL {
                ShareSheet(url: url)
            }
        }
        .toolbar(showToolbar ? .visible : .hidden, for: .bottomBar)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    Task { await vm?.delete(currentAsset.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(.red)

                Spacer()

                if let vm, let detail = vm.detail {
                    Button {
                        Task { await vm.toggleArchive(currentAsset.id) }
                    } label: {
                        Image(systemName: detail.isArchived ? "archivebox.fill" : "archivebox")
                    }

                    Button {
                        Task { await vm.toggleFavorite(currentAsset.id) }
                    } label: {
                        Image(systemName: detail.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(detail.isFavorite ? .red : .white)
                    }

                    Button {
                        vm.showInfoPanel = true
                    } label: {
                        Image(systemName: "info.circle")
                    }

                    Button {
                        Task {
                            await shareFile()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            if vm == nil {
                let api = APIClient(session: session)
                let repo = AssetDetailRepository(api: api)
                vm = AssetDetailViewModel(repo: repo)
            }
            await vm?.load(currentAsset.id)
        }
        .onChange(of: currentAsset) { _, newAsset in
            resetZoom()
            Task {
                await vm?.load(newAsset.id)
            }
        }
    }

    private var currentAssetIndex: Int {
        assets.firstIndex(of: currentAsset) ?? 0
    }

    private func resetZoom() {
        withAnimation {
            scale = 1.0
            offset = .zero
        }
    }

    private func shareFile() async {
        guard let vm, let url = vm.downloadUrl(currentAsset.id) else { return }

        do {
            let data = try await URLSession.shared.data(from: url).0
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try data.write(to: tempURL)
            downloadedFileURL = tempURL
            isSharePresented = true
        } catch {
            // Handle error
        }
    }
}

struct PreviewIndicator: View {
    let assets: [AssetLite]
    @Binding var currentAsset: AssetLite
    var onSelect: (AssetLite) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(assets) { asset in
                        Button {
                            onSelect(asset)
                        } label: {
                            AuthImage(assetId: asset.id, thumbhash: asset.thumbhash)
                                .frame(width: 50, height: 50)
                                .clipped()
                                .cornerRadius(4)
                                .opacity(currentAsset.id == asset.id ? 1.0 : 0.6)
                                .border(
                                    currentAsset.id == asset.id ? Color.blue : Color.clear,
                                    width: 2
                                )
                        }
                        .id(asset.id)
                    }
                }
                .padding(8)
                .onAppear {
                    proxy.scrollTo(currentAsset.id, anchor: .center)
                }
                .onChange(of: currentAsset) { _, newAsset in
                    withAnimation {
                        proxy.scrollTo(newAsset.id, anchor: .center)
                    }
                }
            }
            .frame(height: 66)
        }
    }
}

struct ZoomableImageView: View {
    let assetId: String
    var thumbhash: String?
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    var body: some View {
        ZStack {
            AuthImage(assetId: assetId, size: "preview", thumbhash: thumbhash)
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, min(value, 4))
                            },
                        DragGesture()
                            .onChanged { value in
                                if scale > 1 {
                                    offset = value.translation
                                }
                            }
                            .onEnded { _ in
                                withAnimation {
                                    scale = 1
                                    offset = .zero
                                }
                            }
                    )
                )
                .animation(.spring, value: scale)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct VideoPlayerView: View {
    let assetId: String
    @Environment(SessionManager.self) private var session

    var body: some View {
        VStack {
            Text("Video - Coming Soon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}

struct InfoPanel: View {
    let detail: AssetResponseDTO

    var body: some View {
        NavigationStack {
            List {
                Section("File") {
                    LabeledContent("Name", value: detail.originalFileName)
                    LabeledContent("Created", value: detail.fileCreatedAt.formatted(date: .abbreviated, time: .standard))
                    if let size = detail.exifInfo?.fileSizeInByte {
                        LabeledContent("Size", value: formatBytes(size))
                    }
                }

                if let exif = detail.exifInfo {
                    Section("Camera") {
                        if let make = exif.make, let model = exif.model {
                            LabeledContent("Camera", value: "\(make) \(model)")
                        }
                        if let lens = exif.lensModel {
                            LabeledContent("Lens", value: lens)
                        }
                        if let focal = exif.focalLength {
                            LabeledContent("Focal Length", value: "\(focal)mm")
                        }
                        if let f = exif.fNumber {
                            LabeledContent("Aperture", value: String(format: "f/%.1f", f))
                        }
                        if let iso = exif.iso {
                            LabeledContent("ISO", value: "\(iso)")
                        }
                        if let exposure = exif.exposureTime {
                            LabeledContent("Shutter Speed", value: exposure)
                        }
                    }

                    if let width = exif.exifImageWidth, let height = exif.exifImageHeight {
                        Section("Image") {
                            LabeledContent("Resolution", value: "\(width) × \(height)")
                        }
                    }

                    if let lat = exif.latitude, let lon = exif.longitude {
                        Section("Location") {
                            LabeledContent("Coordinates", value: String(format: "%.4f, %.4f", lat, lon))
                            if let city = exif.city {
                                LabeledContent("City", value: city)
                            }
                            if let state = exif.state {
                                LabeledContent("State", value: state)
                            }
                            if let country = exif.country {
                                LabeledContent("Country", value: country)
                            }
                        }
                    }
                }

                if let people = detail.people, !people.isEmpty {
                    Section("People") {
                        ForEach(people) { person in
                            Text(person.name)
                        }
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    let asset = AssetLite(id: "test-123", isVideo: false, ratio: 1.0, thumbhash: nil, createdAt: Date())
    AssetDetailView(currentAsset: asset, assets: [asset])
        .environment(SessionManager())
}
