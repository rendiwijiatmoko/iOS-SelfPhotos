import SwiftUI
import UIKit

/// Pager foto layar detail, ditopang `UICollectionView`.
///
/// Versi SwiftUI-nya harus membangun `ForEach` atas seluruh perpustakaan supaya
/// `scrollPosition(id:)` bisa menemukan halaman tujuan — pada puluhan ribu foto
/// itu mustahil, jadi dulu diakali dengan jendela 25 halaman yang digeser sendiri
/// setiap kali mendekati tepinya. Jendela itulah sumber sebagian besar keanehan
/// pagernya: indeks, `windowStart`, dan `scrollPosition` harus tetap sepakat
/// padahal ketiganya diperbarui di saat yang berbeda.
///
/// `UICollectionView` memaging seluruh daftar tanpa jendela apa pun, dan seperti
/// di grid, sel yang hidup hanya sebanyak yang terlihat.
struct PhotoPagerView: UIViewControllerRepresentable {
    let assets: [AssetLite]
    /// Foto yang sedang tampil. Dua arah: pager melapor saat diusap, dan ikut
    /// berpindah kalau dipilih dari strip thumbnail.
    let currentAssetID: String
    var layout = PhotoPagerLayout()
    /// false saat panel info terbuka atau sedang menyunting deskripsi.
    var isPagingEnabled = true

    var onPageChanged: (AssetLite) -> Void
    var onZoomChanged: (Bool) -> Void
    var onTap: () -> Void
    /// Posisi halaman sebagai pecahan (mis. 12,37) SELAMA pager bergerak.
    ///
    /// Terpisah dari `onPageChanged` dengan sengaja: yang itu mengubah foto yang
    /// sedang dilihat, jadi ia harus menunggu sampai berhenti — kalau tidak,
    /// setiap foto yang cuma terlewat ikut memuat metadata. Yang ini murni untuk
    /// menggeser strip supaya ikut bergerak bersama jari.
    var onScrollProgress: ((Double) -> Void)? = nil
    /// Menyerahkan controller-nya, supaya bar kontrol video bisa menyambung
    /// langsung tanpa melewati `@State`.
    var onControllerReady: ((PhotoPagerController) -> Void)? = nil

    let session: SessionManager

    func makeUIViewController(context: Context) -> PhotoPagerController {
        let controller = PhotoPagerController(loader: PhotoPreviewLoader(session: session))
        bind(controller)
        controller.apply(assets: assets, currentAssetID: currentAssetID)
        controller.apply(layout: layout, isPagingEnabled: isPagingEnabled)
        if let onControllerReady {
            // Di luar siklus pembaruan: menulis `@State` selagi SwiftUI sedang
            // membangun view memicu peringatan "modifying state during update".
            DispatchQueue.main.async { onControllerReady(controller) }
        }
        return controller
    }

    func updateUIViewController(_ controller: PhotoPagerController, context: Context) {
        bind(controller)
        controller.apply(assets: assets, currentAssetID: currentAssetID)
        controller.apply(layout: layout, isPagingEnabled: isPagingEnabled)
    }

    private func bind(_ controller: PhotoPagerController) {
        controller.onPageChanged = onPageChanged
        controller.onZoomChanged = onZoomChanged
        controller.onTap = onTap
        controller.onScrollProgress = onScrollProgress
    }
}

@MainActor
final class PhotoPagerController: UIViewController {
    private let loader: PhotoPreviewLoader

    private var collectionView: UICollectionView!
    private var assets: [AssetLite] = []
    private var assetIndex: [String: Int] = [:]
    private var currentIndex = 0
    private var layoutRules = PhotoPagerLayout()

    /// Penjaga supaya lompatan ke halaman awal hanya sekali, dan hanya setelah
    /// ukurannya nyata.
    private var hasPositioned = false
    /// true selagi kita sendiri yang menggeser halaman, supaya perpindahan itu
    /// tidak dilaporkan balik sebagai usapan pengguna.
    private var isProgrammaticScroll = false

    var onPageChanged: ((AssetLite) -> Void)?
    var onZoomChanged: ((Bool) -> Void)?
    var onTap: (() -> Void)?
    var onScrollProgress: ((Double) -> Void)?
    /// Bar kontrol video; dipegang lemah karena ia hidup di sisi SwiftUI.
    weak var playbackObserver: (any PhotoPlaybackObserver)?

    init(loader: PhotoPreviewLoader) {
        self.loader = loader
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    override func viewDidLoad() {
        super.viewDidLoad()

        let flow = UICollectionViewFlowLayout()
        flow.scrollDirection = .horizontal
        flow.minimumLineSpacing = 0
        flow.minimumInteritemSpacing = 0
        flow.sectionInset = .zero

        collectionView = HorizontalPagingCollectionView(
            frame: view.bounds, collectionViewLayout: flow)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        // Halaman tidak boleh ikut memantul secara vertikal; sumbu itu milik
        // scroll view di dalam sel saat fotonya di-zoom.
        collectionView.alwaysBounceVertical = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.register(
            PhotoPagerCell.self, forCellWithReuseIdentifier: PhotoPagerCell.reuseID)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        view.addSubview(collectionView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ukuran halaman selalu sebesar bounds — inilah syarat `isPagingEnabled`
        // berhenti tepat di batas foto.
        if let flow = collectionView.collectionViewLayout as? UICollectionViewFlowLayout,
           flow.itemSize != collectionView.bounds.size,
           collectionView.bounds.width > 0 {
            flow.itemSize = collectionView.bounds.size
            flow.invalidateLayout()
            // Bounds berubah (rotasi, toolbar tampil) menggeser halaman kalau
            // offsetnya dibiarkan; posisinya dikunci ulang ke halaman sekarang.
            scrollToCurrent(animated: false)
        }

        positionAtStartIfNeeded()
    }

    // MARK: - Data

    func apply(assets newAssets: [AssetLite], currentAssetID: String) {
        if !isSameContent(as: newAssets) {
            assets = newAssets
            assetIndex = [:]
            assetIndex.reserveCapacity(newAssets.count)
            for (offset, asset) in newAssets.enumerated() {
                assetIndex[asset.id] = offset
            }
            if isViewLoaded {
                collectionView.reloadData()
                // Ukuran kontennya harus sudah pasti sebelum offset disetel;
                // tanpa ini `setContentOffset` menembak ke luar batas yang masih
                // nol dan langsung dijepit kembali ke awal.
                collectionView.layoutIfNeeded()
            }
        }

        guard let index = assetIndex[currentAssetID] else { return }
        let movedElsewhere = index != currentIndex
        currentIndex = index
        guard isViewLoaded else { return }

        // Penempatan awal dicoba DI SINI, bukan hanya di `viewDidLayoutSubviews`.
        //
        // Daftarnya baru terisi setelah layar detail menjalankan `task`-nya, dan
        // kedatangan data itu tidak selalu memicu layout pass baru pada view
        // controller. Kalau penempatan awal cuma menunggu di sana, pagernya
        // tertinggal di offset nol — dan karena daftarnya menaik, nol itu foto
        // PALING LAMA, bukan yang ditekan.
        if !hasPositioned {
            positionAtStartIfNeeded()
        } else if movedElsewhere {
            // Dipilih dari strip thumbnail, bukan diusap: pagernya yang menyusul.
            scrollToCurrent(animated: false)
        }
    }

    func apply(layout newLayout: PhotoPagerLayout, isPagingEnabled: Bool) {
        layoutRules = newLayout
        guard isViewLoaded else { return }

        collectionView.isScrollEnabled = isPagingEnabled
        for case let cell as PhotoPagerCell in collectionView.visibleCells {
            cell.apply(newLayout)
        }
    }

    /// Pembanding murah: jumlah plus kedua ujungnya.
    private func isSameContent(as other: [AssetLite]) -> Bool {
        assets.count == other.count
            && assets.first?.id == other.first?.id
            && assets.last?.id == other.last?.id
    }

    // MARK: - Posisi

    private func positionAtStartIfNeeded() {
        guard !hasPositioned, isViewLoaded,
              collectionView.bounds.width > 0,
              !assets.isEmpty
        else { return }

        hasPositioned = true
        scrollToCurrent(animated: false)
    }

    private func scrollToCurrent(animated: Bool) {
        guard assets.indices.contains(currentIndex),
              collectionView.bounds.width > 0
        else { return }

        // `setContentOffset`, bukan `scrollToItem`: yang kedua bisa mendarat di
        // tengah halaman kalau layoutnya belum sempat diperbarui, dan pada pager
        // itu berarti dua foto terlihat separuh-separuh.
        isProgrammaticScroll = true
        let offset = CGPoint(
            x: CGFloat(currentIndex) * collectionView.bounds.width, y: 0)
        collectionView.setContentOffset(offset, animated: animated)
        if !animated { isProgrammaticScroll = false }
    }

    private func reportPageIfChanged() {
        guard collectionView.bounds.width > 0 else { return }
        let page = Int(round(collectionView.contentOffset.x / collectionView.bounds.width))
        guard assets.indices.contains(page), page != currentIndex else { return }

        currentIndex = page
        stopPlaybackOnOtherPages()
        reportPlaybackState()
        onPageChanged?(assets[page])
    }

    /// Menghentikan video di halaman yang sudah bukan halaman sekarang.
    ///
    /// Sel tetangga tetap hidup di pager, jadi tanpa ini videonya terus berjalan
    /// di halaman yang sudah lewat — tetap memakan jaringan dan menahan sesi
    /// audio, sementara layarnya sendiri sudah tidak terlihat.
    private func stopPlaybackOnOtherPages() {
        for case let cell as PhotoPagerCell in collectionView.visibleCells {
            guard let path = collectionView.indexPath(for: cell),
                  path.item != currentIndex
            else { continue }
            cell.stopPlayback()
        }
    }

    // MARK: - Kendali video

    /// Sel halaman yang sedang dilihat.
    private var currentCell: PhotoPagerCell? {
        collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0))
            as? PhotoPagerCell
    }

    func togglePlayback() { currentCell?.togglePlayPause() }
    func toggleMute() { currentCell?.toggleMute() }
    func seek(toFraction fraction: Double) { currentCell?.seek(toFraction: fraction) }

    /// Mengabarkan keadaan sekarang — dipakai bar kontrol saat baru menyambung
    /// atau setelah halaman berpindah.
    func reportPlaybackState() {
        playbackObserver?.playbackDidUpdate(currentCell?.playbackState ?? PhotoPlaybackState())
    }

    /// Halaman yang sedang di tengah layar; -1 kalau belum bisa dihitung.
    private var visiblePage: Int {
        guard collectionView.bounds.width > 0 else { return -1 }
        return Int(round(collectionView.contentOffset.x / collectionView.bounds.width))
    }

    /// Setelah berhenti, pastikan halaman ini dan tetangganya punya gambar.
    ///
    /// Prefetch bawaan `UICollectionView` bekerja dengan jendela yang sempit pada
    /// pager, dan gulir cepat membatalkan pemuatan di tengah jalan. Ini murah:
    /// yang sudah ada di memori dijawab seketika, dan permintaan yang sedang
    /// berjalan digabungkan oleh `ImageCache`, bukan diulang.
    private func settleVisiblePages() {
        for case let cell as PhotoPagerCell in collectionView.visibleCells {
            cell.retryIfNeeded(loader: loader)
        }

        let page = visiblePage
        guard page >= 0 else { return }
        let neighbours = [page - 2, page - 1, page + 1, page + 2]
            .filter { assets.indices.contains($0) }
            .map { assets[$0].id }
        guard !neighbours.isEmpty else { return }
        loader.prefetch(neighbours)
    }
}

// MARK: - Sumber data

extension PhotoPagerController: UICollectionViewDataSource {
    func collectionView(
        _ collectionView: UICollectionView, numberOfItemsInSection section: Int
    ) -> Int {
        assets.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PhotoPagerCell.reuseID, for: indexPath)
        guard let pageCell = cell as? PhotoPagerCell,
              assets.indices.contains(indexPath.item)
        else { return cell }

        pageCell.configure(with: assets[indexPath.item], loader: loader)
        pageCell.apply(layoutRules)
        pageCell.onZoomChanged = { [weak self] in self?.onZoomChanged?($0) }
        pageCell.onTap = { [weak self] in self?.onTap?() }
        // Hanya halaman yang sedang dilihat yang boleh melapor; sel tetangga
        // ikut hidup dan laporannya akan menimpa keadaan yang benar.
        pageCell.onPlaybackChanged = { [weak self] state in
            guard let self, indexPath.item == self.currentIndex else { return }
            self.playbackObserver?.playbackDidUpdate(state)
        }
        return pageCell
    }
}

// MARK: - Delegate

extension PhotoPagerController: UICollectionViewDelegate {
    // Pager sengaja TIDAK berdetak: ketukan haptic hanya milik strip thumbnail,
    // supaya satu usapan tidak menghasilkan dua getaran yang saling menimpa.

    /// Melaporkan posisi selama bergerak, bukan hanya saat berhenti.
    ///
    /// Dibatasi pada gerakan yang berasal dari jari. Penggeseran yang kita
    /// lakukan sendiri — mis. saat sebuah thumbnail ditekan — tidak boleh
    /// dilaporkan balik, karena itu justru akan menarik stripnya melawan
    /// perpindahan yang baru saja dimintanya.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || scrollView.isDecelerating,
              collectionView.bounds.width > 0
        else { return }
        onScrollProgress?(Double(collectionView.contentOffset.x / collectionView.bounds.width))
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        reportPageIfChanged()
        settleVisiblePages()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isProgrammaticScroll = false
        reportPageIfChanged()
        settleVisiblePages()
    }

    /// Usapan yang berhenti tanpa deselerasi tetap berpindah halaman.
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        reportPageIfChanged()
        settleVisiblePages()
    }
}

// MARK: - Prefetching

extension PhotoPagerController: UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]
    ) {
        let ids = indexPaths
            .filter { assets.indices.contains($0.item) }
            .map { assets[$0.item].id }
        guard !ids.isEmpty else { return }
        loader.prefetch(ids)
    }
}


/// Collection view yang hanya mau digulir MENDATAR.
///
/// Usapan ke atas di layar detail artinya membuka panel info, dan usapan ke
/// bawah artinya menutup layar. Keduanya jarang benar-benar tegak lurus — selalu
/// ada sedikit komponen mendatar, dan itu sudah cukup membuat pager ikut
/// berpindah foto di tengah gerakan. Menolak gestur yang lebih tegak daripada
/// mendatar sejak awal membuat ketiganya tidak pernah berebut.
private final class HorizontalPagingCollectionView: UICollectionView {
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        if recognizer === panGestureRecognizer {
            let velocity = panGestureRecognizer.velocity(in: self)
            if abs(velocity.y) > abs(velocity.x) { return false }
        }
        return super.gestureRecognizerShouldBegin(recognizer)
    }
}
