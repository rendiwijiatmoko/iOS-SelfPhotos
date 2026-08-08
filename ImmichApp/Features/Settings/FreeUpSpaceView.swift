import SwiftUI

/// Membersihkan salinan lokal yang sudah aman di server.
///
/// Tiga tahapnya sengaja terlihat sekaligus seperti alur di Photos: pilih batas
/// waktu, scan, lalu minta iOS memindahkan hasilnya ke Recently Deleted.
struct FreeUpSpaceView: View {
    private enum AlwaysKeepMedia: String, CaseIterable, Identifiable {
        case none
        case photos
        case videos

        var id: Self { self }

        var title: String {
            switch self {
            case .none: "None"
            case .photos: "Photos"
            case .videos: "Videos"
            }
        }

        var symbol: String {
            switch self {
            case .none: "minus"
            case .photos: "photo.fill"
            case .videos: "video.fill"
            }
        }
    }

    private enum CutoffPreset: String, CaseIterable, Identifiable {
        case days30
        case days60
        case days90
        case year1
        case years2
        case years3

        var id: Self { self }

        var value: String {
            switch self {
            case .days30: "30"
            case .days60: "60"
            case .days90: "90"
            case .year1: "1"
            case .years2: "2"
            case .years3: "3"
            }
        }

        var unit: String {
            switch self {
            case .days30, .days60, .days90: "days"
            case .year1: "year"
            case .years2, .years3: "years"
            }
        }

        func date(from now: Date = .now) -> Date {
            let calendar = Calendar.current
            switch self {
            case .days30: return calendar.date(byAdding: .day, value: -30, to: now) ?? now
            case .days60: return calendar.date(byAdding: .day, value: -60, to: now) ?? now
            case .days90: return calendar.date(byAdding: .day, value: -90, to: now) ?? now
            case .year1: return calendar.date(byAdding: .year, value: -1, to: now) ?? now
            case .years2: return calendar.date(byAdding: .year, value: -2, to: now) ?? now
            case .years3: return calendar.date(byAdding: .year, value: -3, to: now) ?? now
            }
        }
    }

    private enum Stage: Equatable {
        case select
        case scanning
        case review
        case deleting
        case complete
    }

    @State private var library = LocalPhotoLibrary.shared
    @State private var albums: [LocalAlbum] = []
    @State private var isLoadingAlbums = true
    @State private var keepOptionsExpanded = false
    @State private var keepFavorites = true
    @State private var keepAlbumIDs = Set<String>()
    @State private var alwaysKeepMedia = AlwaysKeepMedia.none

    @State private var selectedPreset: CutoffPreset?
    @State private var usesCustomDate = false
    @State private var customDate = Calendar.current.date(
        byAdding: .year,
        value: -1,
        to: .now) ?? .now

    @State private var stage = Stage.select
    @State private var candidates: [LocalSpaceCandidate] = []
    @State private var removedCount = 0
    @State private var actionError: ErrorEvent?

    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 3)

    var body: some View {
        Form {
            introductionSection
            keepSection
            cutoffSection
            scanSection
            removalSection
        }
        .formStyle(.grouped)
        .navigationTitle("Free Up Space")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAlbums() }
        .errorToast($actionError)
        .sensoryFeedback(.success, trigger: removedCount)
    }

    private var introductionSection: some View {
        Section {
            Label {
                Text("Move backed-up photos and videos to Recently Deleted to free up space. Copies on your server remain safe.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 5)
        }
    }

    private var keepSection: some View {
        Section {
            DisclosureGroup(isExpanded: $keepOptionsExpanded) {
                Toggle("Keep Favorites", isOn: $keepFavorites)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Keep Albums")
                        .font(.headline)

                    if isLoadingAlbums {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading albums…")
                                .foregroundStyle(.secondary)
                        }
                    } else if albums.isEmpty {
                        Text(library.isAuthorized
                             ? "No albums are available."
                             : "Photo library access is required to show albums.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(albums) { album in
                            Button {
                                toggleAlbum(album.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: keepAlbumIDs.contains(album.id)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .foregroundStyle(keepAlbumIDs.contains(album.id)
                                                         ? Color.accentColor
                                                         : Color.secondary)
                                    Text(album.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(album.count.formatted())
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 6)

                Picker("Always Keep", selection: $alwaysKeepMedia) {
                    ForEach(AlwaysKeepMedia.allCases) { media in
                        Label(media.title, systemImage: media.symbol)
                            .tag(media)
                    }
                }
                .pickerStyle(.segmented)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep on Device")
                            .font(.headline)
                        Text(keepSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(.tint)
                }
            }
        } footer: {
            Text("Favorites, selected albums, and the selected media type will not be removed from this device.")
        }
        .disabled(stage == .scanning || stage == .deleting)
        .onChange(of: keepFavorites) { _, _ in invalidateResults() }
        .onChange(of: keepAlbumIDs) { _, _ in invalidateResults() }
        .onChange(of: alwaysKeepMedia) { _, _ in invalidateResults() }
    }

    private var cutoffSection: some View {
        Section {
            Text("Keep photos and videos from the last…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(CutoffPreset.allCases) { preset in
                    cutoffButton(preset)
                }
            }
            .padding(.vertical, 2)

            Button {
                selectedPreset = nil
                usesCustomDate = true
                invalidateResults()
            } label: {
                Label("Custom Date", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(usesCustomDate ? .accentColor : .secondary)

            if usesCustomDate {
                DatePicker(
                    "Keep Items After",
                    selection: $customDate,
                    in: ...Date.now,
                    displayedComponents: .date)
                .datePickerStyle(.graphical)
                .onChange(of: customDate) { _, _ in invalidateResults() }
            }

            Button {
                scan()
            } label: {
                Label("Continue", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .tint(.accentColor)
            .foregroundStyle(.primary)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(cutoffDate == nil || stage == .scanning || stage == .deleting)
        } header: {
            stepHeader(1, title: "Select Cutoff Date", active: true)
        }
        .listRowSeparator(.hidden)
    }

    private var scanSection: some View {
        Section {
            switch stage {
            case .select:
                Text("Select a cutoff date, then continue to find backed-up items.")
                    .foregroundStyle(.secondary)
            case .scanning:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning backed-up items…")
                }
            case .review, .deleting:
                if candidates.isEmpty {
                    Label("Nothing to free up", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        candidateSummary,
                        systemImage: "doc.text.magnifyingglass")
                }
            case .complete:
                Label("Scan complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } header: {
            stepHeader(2, title: "Scan", active: stage != .select)
        }
    }

    private var removalSection: some View {
        Section {
            switch stage {
            case .select, .scanning:
                Text("Scan results will appear here.")
                    .foregroundStyle(.secondary)
            case .review:
                if candidates.isEmpty {
                    Text("All eligible items are already protected by your current keep rules, or nothing older than the cutoff is backed up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button(role: .destructive) {
                        moveToRecentlyDeleted()
                    } label: {
                        Label(
                            "Move \(candidates.count.formatted()) Items to Recently Deleted",
                            systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)

                    Text("iOS will ask for final confirmation. You can recover these items from Recently Deleted for a limited time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .deleting:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for Photos…")
                }
            case .complete:
                Label {
                    Text("\(removedCount.formatted()) items moved to Recently Deleted")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        } header: {
            stepHeader(
                3,
                title: "Move to Recently Deleted",
                active: stage == .review || stage == .deleting || stage == .complete)
        }
    }

    private func cutoffButton(_ preset: CutoffPreset) -> some View {
        let selected = selectedPreset == preset && !usesCustomDate

        return Button {
            selectedPreset = preset
            usesCustomDate = false
            invalidateResults()
        } label: {
            VStack(spacing: 2) {
                Text(preset.value)
                    .font(.title2.bold())
                Text(preset.unit)
                    .font(.caption)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                selected ? Color.accentColor : Color.secondary.opacity(0.12),
                in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(stage == .scanning || stage == .deleting)
    }

    private func stepHeader(_ number: Int, title: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            Text(number.formatted())
                .font(.caption.bold())
                .foregroundStyle(active ? Color.white : Color.secondary)
                .frame(width: 26, height: 26)
                .background(
                    active ? Color.accentColor : Color.secondary.opacity(0.2),
                    in: .circle)
            Text(title)
                .font(.headline)
                .foregroundStyle(active ? Color.primary : Color.secondary)
        }
        .textCase(nil)
    }

    private var cutoffDate: Date? {
        if usesCustomDate { return customDate }
        return selectedPreset?.date()
    }

    private var keepSummary: String {
        var values: [String] = []
        if keepFavorites { values.append("Favorites") }
        if !keepAlbumIDs.isEmpty {
            values.append(keepAlbumIDs.count == 1 ? "1 Album" : "\(keepAlbumIDs.count) Albums")
        }
        if alwaysKeepMedia != .none { values.append(alwaysKeepMedia.title) }
        return values.isEmpty ? "Nothing selected" : "Keeping: \(values.joined(separator: ", "))"
    }

    private var candidateSummary: String {
        let photos = candidates.lazy.filter { !$0.isVideo }.count
        let videos = candidates.count - photos
        let photoText = photos == 1 ? "1 photo" : "\(photos) photos"
        let videoText = videos == 1 ? "1 video" : "\(videos) videos"
        return "Found \(photoText) and \(videoText)"
    }

    private func loadAlbums() async {
        albums = await library.albums()
        isLoadingAlbums = false
    }

    private func toggleAlbum(_ id: String) {
        if keepAlbumIDs.contains(id) {
            keepAlbumIDs.remove(id)
        } else {
            keepAlbumIDs.insert(id)
        }
    }

    private func invalidateResults() {
        guard stage == .review || stage == .complete else { return }
        candidates = []
        removedCount = 0
        stage = .select
    }

    private func scan() {
        guard let cutoffDate else { return }

        stage = .scanning
        candidates = []
        removedCount = 0

        let keepFavorites = keepFavorites
        let keepAlbumIDs = keepAlbumIDs
        let keepPhotos = alwaysKeepMedia == .photos
        let keepVideos = alwaysKeepMedia == .videos

        Task {
            let result = await library.freeUpSpaceCandidates(
                olderThan: cutoffDate,
                keepFavorites: keepFavorites,
                keepAlbumIDs: keepAlbumIDs,
                keepPhotos: keepPhotos,
                keepVideos: keepVideos)

            guard stage == .scanning else { return }
            if !library.isAuthorized {
                stage = .select
                actionError = ErrorEvent("Allow full Photos access to scan your library.")
                return
            }

            candidates = result
            stage = .review
        }
    }

    private func moveToRecentlyDeleted() {
        let ids = candidates.map(\.id)
        guard !ids.isEmpty else { return }

        stage = .deleting
        Task {
            guard await library.delete(ids) else {
                stage = .review
                actionError = ErrorEvent("The selected items could not be moved to Recently Deleted.")
                return
            }

            let manager = SwiftDataManager.shared
            for id in ids {
                try? manager.unlinkDeviceAsset(localIdentifier: id)
            }
            BackupService.shared.refreshCounts()

            removedCount = ids.count
            candidates = []
            stage = .complete
        }
    }
}
