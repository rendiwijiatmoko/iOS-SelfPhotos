import SwiftUI

struct AssetDetailView: View {
    let asset: AssetLite
    @Environment(SessionManager.self) private var session
    @State private var vm: AssetDetailViewModel?

    var body: some View {
        ZStack(alignment: .bottom) {
            content

            if vm != nil {
                toolbar
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: Binding(
            get: { vm?.showInfoPanel ?? false },
            set: { vm?.showInfoPanel = $0 }
        )) {
            if let detail = vm?.detail {
                InfoPanel(detail: detail)
                    .presentationDetents([.medium, .large])
            }
        }
        .task {
            if vm == nil {
                let api = APIClient(session: session)
                let repo = AssetDetailRepository(api: api)
                vm = AssetDetailViewModel(repo: repo)
            }
            await vm?.load(asset.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle, .loading:
                ProgressView()

            case .loaded:
                if let detail = vm.detail {
                    if detail.isVideo {
                        VideoPlayerView(assetId: detail.id)
                    } else {
                        AuthImage(assetId: detail.id, size: "preview")
                            .scaledToFit()
                    }
                }

            case .failed(let error):
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
                            await vm.retry(asset.id)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        if let vm, let detail = vm.detail {
            HStack(spacing: 24) {
                Button {
                    Task { await vm.delete(asset.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(.red)

                Spacer()

                Button {
                    Task { await vm.toggleArchive(asset.id) }
                } label: {
                    Image(systemName: detail.isArchived ? "archivebox.fill" : "archivebox")
                }

                Button {
                    Task { await vm.toggleFavorite(asset.id) }
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
                    if let url = vm.downloadUrl(asset.id) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
    }
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
    AssetDetailView(asset: asset)
        .environment(SessionManager())
}
