import SwiftUI

/// Pembungkus supaya kumpulan id bisa dipakai `sheet(item:)`.
///
/// `[String]` bukan `Identifiable`, dan menambahkan konformansi itu ke tipe milik
/// pustaka standar berisiko bentrok dengan deklarasi serupa di tempat lain.
private struct SelectedAssets: Identifiable {
    let id = UUID()
    let ids: [String]
}

struct TimelineView: View {
    /// Naik satu setiap tab Photos ditekan ulang; memicu kembali ke posisi
    /// default, yaitu paling bawah (foto terbaru).
    var resetScrollRequest = 0

    @Environment(SessionManager.self) private var session
    /// Linimasa merender dari hasil sync, jadi ia perlu tahu kapan sync selesai.
    @Environment(SyncViewModel.self) private var syncVM: SyncViewModel?
    @State private var vm: TimelineViewModel?
    @State private var shareFileURL: URL?
    @State private var isSharePresented = false
    @State private var assetToDelete: AssetLite?
    /// Aset yang sedang dipilihkan album lewat sheet.
    @State private var albumPickerAsset: AssetLite?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var showSelectionDeleteConfirm = false
    @State private var isPreparingSelectionShare = false
    @State private var selectionShareURLs: [URL] = []
    @State private var isSelectionSharePresented = false
    /// Naik satu setiap penghapusan yang dikonfirmasi server.
    @State private var deleteFeedback = 0
    /// Naik satu setiap favorit yang dikonfirmasi server.
    @State private var favoriteFeedback = 0
    /// Seleksi yang sedang dipilihkan album; nil berarti sheet-nya tertutup.
    @State private var albumPickerSelection: SelectedAssets?
    @State private var selectionLink: SharedLinkPresentation?
    /// Bulan yang sedang tampil, DI LUAR state milik view ini.
    ///
    /// Sebagai `@State`, setiap perubahannya menginvalidasi seluruh body —
    /// termasuk grid berisi puluhan ribu sel — padahal yang berubah cuma sebaris
    /// teks di toolbar. Dan probe-nya menulis terus selama jari bergerak.
    ///
    /// Sebagai objek `@Observable`, hanya view yang benar-benar MEMBACA judulnya
    /// yang ikut digambar ulang.
    @State private var monthTracker = VisibleMonthTracker()
    @AppStorage(SettingsViewModel.gridColumnsKey) private var gridColumns = 3
    /// Pegangan ke controller grid, untuk perintah yang datang dari luar —
    /// ketukan kedua tab Photos, misalnya.
    @State private var gridController: PhotoGridController?

    var body: some View {
        NavigationStack {
            content
                // TANPA `toolbarBackground` sama sekali — latarnya diserahkan
                // ke sistem, dan di iOS 26 itulah yang memberi kaca transparan.
                //
                // Judulnya bukan `navigationTitle` melainkan toolbar item biasa
                // (lihat `timelineToolbar`), karena item toolbar tidak pernah
                // menyusut atau berpindah ke tengah saat di-scroll.
                .toolbar { timelineToolbar }
                // Tab bar diganti bottom bar selama memilih, supaya aksi
                // seleksi menempati tempat yang sama.
                .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
                .toolbar(isSelecting ? .visible : .hidden, for: .bottomBar)
        }
        .sheet(isPresented: $isSharePresented) {
            if let url = shareFileURL {
                ShareSheet(url: url)
            }
        }
        .sheet(item: $albumPickerAsset) { asset in
            AlbumPickerSheet(albums: vm?.albums ?? []) { album in
                Task { await vm?.addToAlbum(asset, album: album) }
            }
        }
        .sheet(isPresented: $isSelectionSharePresented) {
            MultiShareSheet(urls: selectionShareURLs)
        }
        .sheet(item: $albumPickerSelection) { selection in
            AlbumPickerSheet(albums: vm?.albums ?? []) { album in
                runSelection { await vm?.addToAlbum(selection.ids, album: album) }
            }
        }
        .sheet(item: $selectionLink) { ShareSheet(url: $0.url) }
        // Dialognya menempel di layar, bukan di tombol sampahnya: tombol itu
        // sekarang hidup di dalam `SelectionToolbar`.
        .confirmationDialog(
            deleteConfirmTitle,
            isPresented: $showSelectionDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Action Failed", isPresented: Binding(
            get: { vm?.actionError != nil },
            set: { if !$0 { vm?.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm?.actionError ?? "")
        }
        .alert("Delete Photo", isPresented: Binding(
            get: { assetToDelete != nil },
            set: { if !$0 { assetToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let asset = assetToDelete {
                    Task {
                        if await vm?.delete(asset) == true {
                            deleteFeedback += 1
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this photo?")
        }
        // Ketukan tegas hanya setelah server mengonfirmasi penghapusan.
        .sensoryFeedback(.impact(weight: .heavy), trigger: deleteFeedback)
        // Favorit BUKAN ketukan berat: hasilnya bukan sesuatu yang hilang,
        // melainkan sesuatu yang bertambah — `.success` yang menyampaikannya.
        .sensoryFeedback(.success, trigger: favoriteFeedback)
        .task {
            if vm == nil {
                let api = APIClient(session: session)
                vm = TimelineViewModel(
                    dataManager: SwiftDataManager.shared,
                    assetRepo: AssetDetailRepository(api: api),
                    albumRepo: AlbumRepository(api: api)
                )
            }
            await vm?.loadTimelineIfNeeded()
            await vm?.loadAlbumsIfNeeded()
        }
        // Sync pertama biasanya selesai SETELAH layar ini muncul; tanpa ini
        // grid-nya tetap kosong sampai tab dibuka ulang.
        .onChange(of: syncVM?.lastSyncTime) { _, _ in
            Task { await vm?.loadTimeline() }
        }
        // Ketukan kedua pada tab Photos. Dikirim AppRouter sebagai penghitung
        // yang naik, bukan Bool, supaya ketukan beruntun tetap terbaca.
        .onChange(of: resetScrollRequest) { _, _ in
            guard let vm else { return }
            returnToNewest(vm)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle, .loading:
                // Kosong, BUKAN spinner, kalau fotonya sudah ada di perangkat.
                //
                // Yang ditunggu cuma pembacaan cache dan pengelompokannya —
                // sepersekian detik, dan tidak ada yang sedang diunduh. Spinner
                // di situ membuat aplikasi seolah memuat ulang seluruh isinya
                // setiap kali dibuka, padahal isinya sudah lama tersimpan.
                if vm.hasLocalData {
                    Color.clear
                } else {
                    ProgressView()
                }

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
            // View model baru dibuat di `task`, yaitu setelah gambar pertama.
            // Satu frame kosong jauh lebih tenang daripada spinner yang berkedip
            // dan langsung hilang.
            Color.clear
        }
    }

    private func timelineGrid(_ vm: TimelineViewModel) -> some View {
        PhotoGridView(
            sections: vm.sections,
            configuration: PhotoGridConfiguration(
                columns: max(gridColumns, 1),
                // TANPA judul bulan menempel di grid.
                //
                // Bulan yang sedang tampil sudah tertulis di bawah "Photos" di
                // toolbar, jadi judul kedua di dalam grid cuma mengulang. Dan
                // begitu judulnya tidak ada, memecah grid per bulan pun tidak
                // punya alasan lagi — barisnya mengalir terus melewati pergantian
                // bulan, tanpa petak kosong di ujung tiap bulan.
                showsSectionHeaders: false,
                startsAtNewest: true,
                // Linimasa dibaca dari bawah, jadi baris bolongnya ditaruh di
                // puncak — tempat yang hampir tidak pernah dilihat.
                padsFirstRow: true),
            isSelecting: $isSelecting,
            selectedIDs: $selectedIDs,
            detailScreen: { id in detailScreen(for: id, vm) },
            onVisibleSectionChanged: { monthTracker.show($0) },
            menuActions: { id in menuActions(for: id, vm) },
            onControllerReady: { gridController = $0 },
            session: session)
        // Grid menembus sampai ke BELAKANG nav bar, bukan berhenti di bawahnya.
        //
        // Inilah sebab toolbar-nya terlihat berlatar warna polos: bar-nya sendiri
        // sudah transparan, tapi yang berada di belakangnya cuma latar collection
        // view — fotonya tidak pernah sampai ke sana karena framenya berhenti
        // tepat di bawah bar. Kaca tidak punya apa-apa untuk diburamkan.
        //
        // Setelah framenya melebar, `contentInsetAdjustmentBehavior` bawaan tetap
        // menahan baris pertama di bawah bar, jadi tidak ada foto yang tertutup —
        // yang berubah cuma: sekarang foto lewat di belakangnya saat digulir.
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    /// Isi context menu, dibangun SAAT foto ditekan lama.
    ///
    /// Dulu tiap sel memasang context menu sendiri begitu ia masuk layar. Di
    /// grid yang digulir cepat itu puluhan pemasangan interaksi per detik, untuk
    /// menu yang hampir tidak pernah dibuka.
    private func menuActions(
        for id: String,
        _ vm: TimelineViewModel
    ) -> [PhotoGridMenuAction] {
        guard let asset = vm.asset(for: id) else { return [] }
        return [
            // Tiga teratas jadi BARIS IKON di puncak menu — lihat
            // `PhotoGridMenuGroup`.
            PhotoGridMenuAction(
                title: String(localized: "Share"),
                systemImage: "square.and.arrow.up",
                group: .quick
            ) {
                Task { await shareAsset(asset, vm) }
            },
            PhotoGridMenuAction(
                title: asset.isFavorite
                    ? String(localized: "Unfavorite")
                    : String(localized: "Favorite"),
                systemImage: asset.isFavorite ? "heart.fill" : "heart",
                group: .quick
            ) {
                Task {
                    // Getarnya HANYA setelah server menerimanya. Bergetar lebih
                    // dulu berarti memberi tahu "sudah" untuk sesuatu yang belum
                    // tentu terjadi.
                    if await vm.toggleFavorite(asset) { favoriteFeedback += 1 }
                }
            },
            PhotoGridMenuAction(
                title: String(localized: "Archive"),
                systemImage: "archivebox",
                group: .quick
            ) {
                Task { await vm.archive(asset) }
            },
            PhotoGridMenuAction(
                title: String(localized: "Add to Album"),
                systemImage: "rectangle.stack.badge.plus"
            ) {
                albumPickerAsset = asset
            },
            PhotoGridMenuAction(
                title: String(localized: "Move to Locked Folder"),
                systemImage: "lock"
            ) {
                Task { await vm.lockSelected([asset.id]) }
            },
            PhotoGridMenuAction(title: String(localized: "Share Link"), systemImage: "link") {
                createSharedLink(for: [asset.id])
            },
            PhotoGridMenuAction(
                title: String(localized: "Delete"),
                systemImage: "trash",
                isDestructive: true
            ) {
                assetToDelete = asset
            },
        ]
    }

    private var selectButton: some View {
        Button {
            if isSelecting {
                exitSelection()
            } else {
                isSelecting = true
            }
        } label: {
            if isSelecting {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
            } else {
                Text("Select")
            }
        }
    }

    /// Judul + bulan yang sedang di layar, keduanya di dalam satu toolbar item.
    ///
    /// Sengaja TANPA foregroundStyle: warna bawaan item toolbar sudah vibrant
    /// terhadap apa yang lewat di belakangnya — mekanisme yang sama dengan
    /// label tombol Select. Menyetelnya justru mengunci warnanya.
    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Photos")
                .font(.largeTitle.bold())

            VisibleMonthLabel(tracker: monthTracker)
        }
        .lineLimit(1)
        // WAJIB: tanpa ini toolbar menyempitkan item sampai selebar ikon dan
        // judulnya tersisa jadi "…".
        .fixedSize()
    }

    // MARK: - Sel grid

    /// Layar detail, dibangun untuk dipresentasikan oleh grid.
    ///
    /// Isinya sama persis dengan yang dulu ada di `fullScreenCover`; yang pindah
    /// hanya siapa yang membukanya, supaya animator transisi punya tempat.
    private func detailScreen(for id: String, _ vm: TimelineViewModel) -> AnyView {
        guard let asset = vm.asset(for: id) else { return AnyView(EmptyView()) }

        return AnyView(
            NavigationStack {
                AssetDetailView(
                    currentAsset: asset,
                    assets: vm.allAssets,
                    isModal: true,
                    // Menutupnya harus mengecil ke foto yang SEDANG dilihat,
                    // bukan yang pertama dibuka.
                    onAssetChange: { gridController?.detailDidChangeAsset(to: $0.id) },
                    // Grid ikut diperbarui saat layar detail masih terbuka, jadi
                    // saat kembali isinya sudah konsisten dengan server.
                    onAssetRemoved: { vm.assetWasRemoved($0) },
                    onAssetUpdated: { removedID in
                        Task { await vm.assetWasUpdated(removedID) }
                    },
                    onFavoriteChanged: { favoriteID, isFavorite in
                        vm.setFavorite(favoriteID, to: isFavorite)
                    }
                )
            }
            // Keyboard avoidance ditolak di AKAR scene yang dipresentasikan:
            // inset keyboard dipasang oleh hosting controller-nya, dan opt-out
            // dari dalam NavigationStack tidak bisa membatalkan penyusutan yang
            // sudah terjadi di atasnya.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .environment(session)
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var timelineToolbar: some ToolbarContent {
        // Judul sebagai toolbar item, bukan navigationTitle: posisinya tetap,
        // tidak ikut menyusut ke inline saat di-scroll.
        // Judul disembunyikan selama memilih: jumlah terpilih menempati posisi
        // principal, dan UIKit memusatkan `titleView` di antara item bar — dengan
        // judul besar masih di kiri, jumlahnya terjepit sampai terpotong.
        if !isSelecting {
            ToolbarItem(placement: .topBarLeading) { titleStack }
                // Judul tidak boleh dapat latar kapsul seperti tombol.
                .sharedBackgroundVisibility(.hidden)
        }

        ToolbarItem(placement: .topBarTrailing) { selectButton }

        if isSelecting {
            // Jumlahnya pindah ke bar ATAS: bar bawah sekarang penuh aksi, dan
            // menyelipkan teks di antaranya hanya membuat tombolnya berdesakan.
            ToolbarItem(placement: .principal) { selectionCountLabel }
                .sharedBackgroundVisibility(.hidden)

            SelectionToolbar(actions: selectionActions)
        }
    }

    /// Aksi mode pilih untuk linimasa.
    private var selectionActions: SelectionActions {
        let ids = Array(selectedIDs)
        var actions = SelectionActions()
        actions.isBusy = isPreparingSelectionShare || selectedIDs.isEmpty

        actions.share = { shareSelection() }
        actions.favorite = {
            runSelection {
                if await vm?.favoriteSelected(ids) == true { favoriteFeedback += 1 }
            }
        }
        actions.archive = { runSelection { await vm?.archiveSelected(ids) } }
        actions.trash = { showSelectionDeleteConfirm = true }
        actions.menu = [
            SelectionMenuAction(title: "Share Link", systemImage: "link") {
                createSharedLink(for: ids)
            },
            SelectionMenuAction(
                title: "Add to Album",
                systemImage: "rectangle.stack.badge.plus"
            ) {
                albumPickerSelection = SelectedAssets(ids: ids)
            },
            SelectionMenuAction(title: "Move to Locked Folder", systemImage: "lock") {
                runSelection { await vm?.lockSelected(ids) }
            },
        ]
        return actions
    }

    private func createSharedLink(for ids: [String]) {
        guard !ids.isEmpty else { return }
        let repo = SharedLinkRepository(api: APIClient(session: session))
        Task {
            guard let link = try? await repo.create(assetIds: ids),
                  let url = link.publicURL(base: session.baseURL)
            else { return }
            selectionLink = SharedLinkPresentation(url: url)
        }
    }

    private func runSelection(_ work: @escaping () async -> Void) {
        Task {
            await work()
            exitSelection()
        }
    }

    private var selectionCountLabel: some View {
        Text(selectionTitle)
            .font(.headline.bold())
            .foregroundStyle(selectedIDs.isEmpty ? .secondary : .primary)
            .lineLimit(1)
            // Tanpa fixedSize, toolbar menyempitkan teksnya sampai terpotong.
            .fixedSize()
    }

    /// Sengaja dirakit manual, bukan `^[...](inflect:)`.
    ///
    /// Markup inflect hanya diproses kalau string-nya berupa literal yang
    /// menjadi `LocalizedStringKey`. Membangunnya lebih dulu sebagai `String`
    /// membuat `Text` menampilkannya apa adanya — markup-nya ikut terbaca.
    private var selectionTitle: String {
        let count = selectedIDs.count
        guard count > 0 else { return String(localized: "Select Items") }
        return count == 1 ? "1 Item Selected" : "\(count) Items Selected"
    }

    private var deleteConfirmTitle: String {
        let count = selectedIDs.count
        return count == 1 ? "Delete 1 Item" : "Delete \(count) Items"
    }

    // MARK: - Aksi seleksi

    private func exitSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    /// Ketukan kedua di tab Photos: kembali ke foto terbaru SEKALIGUS memuat
    /// ulang.
    ///
    /// Menggantikan tarik-untuk-menyegarkan, yang letaknya justru di ujung yang
    /// salah — foto terbaru ada di bawah, sedangkan tarikan itu hanya bisa
    /// dilakukan dari puncak, tempat foto paling lama berada.
    private func returnToNewest(_ vm: TimelineViewModel) {
        // Beranimasi, bukan melompat: perpindahan sebesar ini tanpa gerakan
        // membuat pengguna kehilangan pegangan tentang ke mana ia baru saja
        // dibawa. Jaraknya ditempuh penuh; ongkosnya ditekan dengan
        // menghentikan pemuatan thumbnail selama terbang — lihat
        // `scrollToNewest(animated:)`.
        gridController?.scrollToNewest(animated: true)

        // Penyegaran DITUNDA sampai terbangnya benar-benar selesai.
        //
        // Menyegarkan berarti menarik PERUBAHAN dari server lalu menyusun ulang
        // dari cache — bukan mengunduh ulang linimasanya. Tapi menyusun ulang itu
        // memasang snapshot untuk puluhan ribu item, dan kalau jatuh bersamaan
        // dengan animasinya, gerakannya macet lalu lanjut lagi. Kalau jatuh tepat
        // sesudahnya, dasar linimasa bergeser dan yang terlihat lompatan kedua.
        //
        // Ditunda, keduanya hilang: satu gerakan bersih, lalu penyegarannya
        // menyusul sebagai kejadian tersendiri.
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            await syncVM?.performBackgroundSync()
            await vm.loadTimeline()
        }
    }

    private func shareSelection() {
        let ids = Array(selectedIDs)
        isPreparingSelectionShare = true
        Task {
            let urls = await vm?.shareURLs(for: ids) ?? []
            isPreparingSelectionShare = false
            guard !urls.isEmpty else { return }
            selectionShareURLs = urls
            isSelectionSharePresented = true
        }
    }

    private func deleteSelection() {
        let ids = Array(selectedIDs)
        Task {
            if await vm?.deleteSelected(ids) == true {
                deleteFeedback += 1
            }
            exitSelection()
        }
    }

    private func shareAsset(_ asset: AssetLite, _ vm: TimelineViewModel) async {
        if let url = await vm.shareURL(for: asset) {
            shareFileURL = url
            isSharePresented = true
        }
    }

    /// Kosong punya DUA arti sekarang, dan keduanya menuntut kalimat berbeda:
    /// perpustakaan yang memang masih kosong, atau sync pertama yang belum
    /// selesai menurunkan datanya.
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            if syncVM?.isSyncing == true {
                ProgressView()
                Text("Syncing your library…")
                    .font(.headline)
                Text("This only happens once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Photos")
                    .font(.headline)
                Text("Upload photos to see them here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
